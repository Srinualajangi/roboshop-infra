#!/usr/bin/env python3
"""List resources that cost money but look unused. Read-only: it never deletes anything."""
import datetime as dt
import boto3

REQUIRED_TAGS = {"Project", "Owner", "ManagedBy"}

def find_orphans(region: str = "us-east-1", snapshot_age_days: int = 30) -> list[str]:
    ec2 = boto3.client("ec2", region_name=region)
    out: list[str] = []

    for v in ec2.describe_volumes(Filters=[{"Name": "status", "Values": ["available"]}])["Volumes"]:
        out.append(f"UNATTACHED_EBS  {v['VolumeId']}  {v['Size']}GiB  created {v['CreateTime']:%F}")

    for a in ec2.describe_addresses()["Addresses"]:
        if "AssociationId" not in a:
            out.append(f"UNUSED_EIP      {a.get('PublicIp')}  {a.get('AllocationId')}")

    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=snapshot_age_days)
    for s in ec2.describe_snapshots(OwnerIds=["self"])["Snapshots"]:
        if s["StartTime"] < cutoff:
            out.append(f"OLD_SNAPSHOT    {s['SnapshotId']}  {s['VolumeSize']}GiB  {s['StartTime']:%F}  {s.get('Description','')[:40]}")

    pages = ec2.get_paginator("describe_instances").paginate()
    for page in pages:
        for r in page["Reservations"]:
            for i in r["Instances"]:
                state = i["State"]["Name"]
                tags = {t["Key"] for t in i.get("Tags", [])}
                if state == "stopped":
                    out.append(f"STOPPED_EC2     {i['InstanceId']}  (EBS still billed)")
                if state != "terminated" and not REQUIRED_TAGS <= tags:
                    out.append(f"MISSING_TAGS    {i['InstanceId']}  missing {sorted(REQUIRED_TAGS - tags)}")
    return out

if __name__ == "__main__":
    found = find_orphans()
    print("\n".join(found) if found else "No orphans found 🎉")
