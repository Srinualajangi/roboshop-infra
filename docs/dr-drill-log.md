## $(date +%F) — namespace loss drill (kind, Velero $VELERO_VERSION, kopia fs-backup)
- Scenario: roboshop-prod namespace deleted
- Backup: prod-drill-1 (objects + PVC data for mongodb, mysql)
- Disaster at: $(cat /tmp/t0) UTC · Service healthy at: $(cat /tmp/t1) UTC · **Measured RTO: __ min**
- RPO: data written after the backup was lost (marker DR-after-backup missing) → RPO = backup interval
- Surprises / fixes: __
- Production improvement: scheduled backups (velero schedule create prod-hourly --schedule="0 * * * *"), off-cluster copy, restore test monthly
