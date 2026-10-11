# roboshop-infra/terraform/modules/vpc/main.tf
locals {
  public_cidrs = [for i, az in var.azs : cidrsubnet(var.cidr, 8, i)]      # 10.40.0.0/24, 10.40.1.0/24
  app_cidrs    = [for i, az in var.azs : cidrsubnet(var.cidr, 4, i + 1)]  # 10.40.16.0/20, 10.40.32.0/20
  data_cidrs   = [for i, az in var.azs : cidrsubnet(var.cidr, 8, 48 + i)] # 10.40.48.0/24, 10.40.49.0/24
  nat_count    = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0
  eks_tag      = var.cluster_name == "" ? {} : { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
  karpenter    = var.cluster_name == "" ? {} : { "karpenter.sh/discovery" = var.cluster_name }
  # one NACL rule per (app CIDR, port) pair, numbered 100, 101, 102 ...
  data_rules = [for i, p in setproduct(local.app_cidrs, var.data_ports) : { n = 100 + i, cidr = p[0], port = p[1] }]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true # required for EKS, VPC endpoints and RDS DNS names
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# ---------- public tier: ALB + NAT only ----------
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false # nothing we launch here needs an auto public IP; NAT uses an EIP, ALB gets its own
  tags = merge(local.eks_tag, {
    Name                     = "${var.name}-public-${var.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # AWS Load Balancer Controller: internet-facing ALBs go here
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id # THIS route is what makes a subnet "public"
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- NAT: egress for the app tier ----------
resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${var.azs[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # a NAT gateway lives in a PUBLIC subnet
  tags          = { Name = "${var.name}-nat-${var.azs[count.index]}" }
  depends_on    = [aws_internet_gateway.this]
}

# ---------- private app tier: EKS nodes and pods ----------
resource "aws_subnet" "app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.app_cidrs[count.index]
  tags = merge(local.eks_tag, local.karpenter, {
    Name                              = "${var.name}-app-${var.azs[count.index]}"
    Tier                              = "app"
    "kubernetes.io/role/internal-elb" = "1" # internal load balancers go here
  })
}

resource "aws_route_table" "app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-app-${var.azs[count.index]}" }
}

resource "aws_route" "app_nat" {
  count                  = var.enable_nat_gateway ? length(var.azs) : 0
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # single NAT: every AZ uses NAT[0]. Per-AZ NAT: each AZ uses its own (AZ failure does not cut egress).
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# ---------- private data tier: no route to the internet at all ----------
resource "aws_subnet" "data" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.data_cidrs[count.index]
  tags              = { Name = "${var.name}-data-${var.azs[count.index]}", Tier = "data" }
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-data" } # only the implicit "local" route: VPC-internal traffic
}

resource "aws_route_table_association" "data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# NACL on the data tier: stateless, so the return traffic needs its own rule
resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.data[*].id
  tags       = { Name = "${var.name}-data" }

  dynamic "ingress" {
    for_each = { for r in local.data_rules : r.n => r }
    content {
      rule_no    = ingress.value.n
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value.cidr
      from_port  = ingress.value.port
      to_port    = ingress.value.port
    }
  }

  dynamic "egress" {
    for_each = local.app_cidrs
    content {
      rule_no    = 100 + egress.key
      protocol   = "tcp"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024 # replies go back to the client's ephemeral port
      to_port    = 65535
    }
  }
}

# Free S3 gateway endpoint: S3 traffic from app/data tiers skips the NAT (saves $0.045/GB)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.app[*].id, [aws_route_table.data.id])
  tags              = { Name = "${var.name}-s3" }
}

data "aws_region" "current" {}

# ---------- optional flow logs (Day 97) ----------
resource "aws_cloudwatch_log_group" "flow" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/roboshop/vpc-flow-logs"
  retention_in_days = 1
}

resource "aws_iam_role" "flow" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.name}-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "flow" {
  count = var.enable_flow_logs ? 1 : 0
  role  = aws_iam_role.flow[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = var.enable_flow_logs ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow[0].arn
  log_destination = aws_cloudwatch_log_group.flow[0].arn
}
