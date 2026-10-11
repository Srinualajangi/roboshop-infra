# roboshop-infra/scripts/test_orphans.py
import boto3
from moto import mock_aws
from orphans import find_orphans

@mock_aws
def test_unattached_volume_and_eip_are_reported():
    ec2 = boto3.client("ec2", region_name="us-east-1")
    ec2.create_volume(AvailabilityZone="us-east-1a", Size=8)
    ec2.allocate_address(Domain="vpc")
    found = find_orphans()
    assert any(l.startswith("UNATTACHED_EBS") for l in found)
    assert any(l.startswith("UNUSED_EIP") for l in found)
