#!/usr/bin/env python3
"""7-day AWS cost by service (Cost Explorer). Each run = 1 API call = $0.01."""
import datetime as dt
import boto3

def main(days: int = 7) -> None:
    ce = boto3.client("ce", region_name="us-east-1")          # Cost Explorer's endpoint is us-east-1
    end = dt.date.today()                                     # End is exclusive
    start = end - dt.timedelta(days=days)
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )
    totals: dict[str, float] = {}
    for day in resp["ResultsByTime"]:
        for g in day["Groups"]:
            svc = g["Keys"][0]
            totals[svc] = totals.get(svc, 0.0) + float(g["Metrics"]["UnblendedCost"]["Amount"])
    grand = sum(totals.values())
    print(f"AWS cost {start} .. {end - dt.timedelta(days=1)}  (total ${grand:.2f})")
    for svc, amt in sorted(totals.items(), key=lambda kv: -kv[1]):
        if amt >= 0.005:
            print(f"  {svc:<55} ${amt:7.2f}  {100 * amt / grand if grand else 0:5.1f}%")

if __name__ == "__main__":
    main()
