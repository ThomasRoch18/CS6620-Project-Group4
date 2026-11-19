# Contracts: Unified Security Hub

Shared formats every component must follow. Changing anything here needs agreement from the whole team.

---

## 1. SQS messages

### SAST queue (`ush-{env}-sast-queue`)

```json
{
  "scanId": "uuid",
  "type": "SAST",
  "mode": "snippet | zip",
  "code": "const password = \"admin123\";",
  "s3Key": "uploads/{scanId}.zip",
  "teamId": "team-a"
}
```

- `mode = snippet` sends `code`, and `s3Key` is omitted.
- `mode = zip` sends `s3Key`, and `code` is omitted.

### Pentest queue (`ush-{env}-pentest-queue`)

```json
{
  "scanId": "uuid",
  "type": "PENTEST",
  "targetUrl": "https://example.com/api/users",
  "teamId": "team-a"
}
```

---

## 2. DynamoDB item (`ush-{env}-scans`)

| Field | Type | Notes |
|---|---|---|
| `scanId` | string | Partition key (UUID) |
| `teamId` | string | GSI1 partition key |
| `createdAt` | string | ISO 8601, GSI1 sort key |
| `type` | string | `SAST` or `PENTEST` |
| `target` | string | Snippet preview, S3 key, or URL |
| `status` | string | `QUEUED`, `RUNNING`, `COMPLETE` or `FAILED` |
| `activeStatus` | string | GSI2 partition key. Set only while `QUEUED` or `RUNNING`; removed when finished |
| `updatedAt` | string | ISO 8601, GSI2 sort key |
| `severityCounts` | map | `{ "HIGH": 2, "MEDIUM": 3, "LOW": 1 }` |
| `s3ReportKey` | string | `reports/{scanId}.json` |
| `errorMessage` | string | Only when `FAILED` |
| `attempts` | number | Incremented each time a worker starts the job |
| `ttl` | number | Epoch seconds for auto-expiry |

### Indexes

| Index | Partition key | Sort key | Used for |
|---|---|---|---|
| Table | `scanId` | none | Get one scan |
| GSI1 | `teamId` | `createdAt` | A team's scans, newest first |
| GSI2 (sparse) | `activeStatus` | `updatedAt` | Sweeper finds stuck jobs |

### Who writes which status

| Writer | Transition | Condition |
|---|---|---|
| Dashboard | creates `QUEUED` | item must not already exist |
| Worker | `QUEUED` → `RUNNING` | status is `QUEUED` |
| Worker | `RUNNING` → `COMPLETE` | status is `RUNNING` |
| Reconciler / sweeper | `QUEUED` or `RUNNING` → `FAILED` | status is `QUEUED` or `RUNNING` |

All writes are conditional, so retries and races never overwrite a finished job.

---

## 3. S3 paths (`ush-{env}-reports-{accountId}`)

| Path | Written by | Contents |
|---|---|---|
| `uploads/{scanId}.zip` | Browser (presigned URL) | Repo zip for SAST |
| `reports/{scanId}.json` | Worker | Full report (format below) |

---

## 4. Report JSON (both scan types)

```json
{
  "scanId": "uuid",
  "type": "SAST | PENTEST",
  "target": "...",
  "startedAt": "2026-11-16T15:00:00Z",
  "completedAt": "2026-11-16T15:00:04Z",
  "summary": { "HIGH": 2, "MEDIUM": 3, "LOW": 1 },
  "results": {}
}
```

- `results` is the raw output of `scanner.js` (SAST) or `tester.js` (pentest), unchanged.
- `summary` uses the same counts as `severityCounts` in DynamoDB.

---

## 5. Pentest task (ECS RunTask)

- `startedBy` = `scanId`. The reconciler uses this to map ECS stopped events back to the job.
- Environment overrides: `SCAN_ID`, `TARGET_URL`, `TEAM_ID`.

---

## 6. Naming and tags

- **Resource names:** `ush-{env}-{resource}`, for example `ush-dev-scans` or `ush-dev-sast-queue`.
- **Environments:** `dev` (personal accounts) and `prod` (main demo account).
- **Tags on every resource**, set with the Terraform `default_tags`:
  - `Project = unified-security-hub`
  - `Environment = dev | prod`
  - `Owner = <person>`
  - `ManagedBy = terraform`

---

## 7. Environment variables

| Variable | Used by |
|---|---|
| `TABLE_NAME` | All |
| `REPORTS_BUCKET` | Dashboard, workers |
| `SAST_QUEUE_URL` | Dashboard |
| `PENTEST_QUEUE_URL` | Dashboard |
| `ECS_CLUSTER`, `TASK_DEFINITION`, `SUBNET_IDS`, `SECURITY_GROUP_ID` | Dispatcher |
| `FINDINGS_TOPIC_ARN` | Notifier |

No hardcoded names or ARNs in code.
