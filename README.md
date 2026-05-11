# Data Pike

A streaming data pipeline built with Apache Flink on AWS Managed Service for Apache Flink. Ingests files from S3 in multiple formats (JSON, XML, delimited), processes weather observation data, computes temperature summaries, and writes output to Apache Iceberg tables.

## Architecture

```
S3 (file upload) → EventBridge → Kinesis Data Stream → Apache Flink (MSF) → Iceberg (via Glue Catalog)
```

1. A file lands in the S3 input bucket
2. S3 emits an `Object Created` event to EventBridge; an EventBridge rule routes it to Kinesis Data Stream
3. Flink (running on Managed Service for Apache Flink) consumes the Kinesis notification, reads the original file from S3, detects its format, and parses it
4. Processed temperature summary records are written to an Apache Iceberg table backed by S3 and cataloged in AWS Glue

## Supported File Formats

- JSON
- XML
- Delimited (CSV, TSV, pipe-separated, etc.)

## Tech Stack

- Java 17
- Apache Flink 2.2.0 (`flink-connector-aws-kinesis-streams` 6.0.0-2.0)
- Apache Iceberg 1.10.1 (Glue catalog in cloud, JDBC catalog locally)
- Lombok 1.18.44
- Jackson (transitive via Iceberg)
- AWS SDK v2 (Kinesis, S3)
- Terraform (infrastructure as code)

## Prerequisites

- Java 17+
- Maven 3.8+
- AWS CLI configured with appropriate credentials. Set your profile before running any AWS or Terraform commands:
  ```bash
  export AWS_PROFILE=yourprofile
  ```
- Terraform >= 1.5.0

## Build

```bash
mvn clean package
```

## Test

```bash
mvn test
```

Some tests deliberately exercise the retry-failure path and emit `ERROR`-level log lines (e.g. `Failed to write to Iceberg table … after 3 retries`). This is expected — the test passes by asserting the exception is thrown. Confirm the build succeeded by checking the summary line at the bottom of the Maven output:

```
Tests run: 49, Failures: 0, Errors: 0, Skipped: 1
```

## Cloud Runtime Properties

On Managed Service for Apache Flink, the application reads its configuration from `/etc/flink/application_properties.json`, which MSF writes before the Job Manager starts. Configure the following property groups in the MSF application's `EnvironmentProperties`:

**`KinesisSource`**
| Key | Description |
|---|---|
| `stream.arn` | Full ARN of the Kinesis Data Stream |
| `aws.region` | AWS region (e.g. `us-east-1`) |

**`IcebergSink`**
| Key | Description |
|---|---|
| `warehouse.path` | S3 URI for the Iceberg warehouse (e.g. `s3://bucket/warehouse`) |
| `catalog.name` | Iceberg catalog name (e.g. `glue_catalog`) |
| `table.name` | Fully-qualified table name (e.g. `weather_data_hub.temperature`) |

If `application_properties.json` is absent (non-MSF environments), the application falls back to CLI args in `--KinesisSource.stream.arn=<value>` format, then to environment variables:

```
KINESIS_STREAM_ARN
AWS_REGION
ICEBERG_WAREHOUSE_PATH
ICEBERG_CATALOG_NAME
ICEBERG_TABLE_NAME
```

## Local Mode

Local development uses [MiniStack](https://ministack.dev) — an AWS-compatible emulator. The pipeline runs the **exact same Kinesis + S3 code path** as production.

### Prerequisites

- Docker (same as `LOCAL` mode)
- AWS CLI v2 (`aws`) configured with any region; credentials are not validated against real AWS

### Start the stack

```bash
./scripts/localaws-up.sh
```

This will:
1. Build the JAR
2. Start MiniStack, Postgres, Flink job-/task-manager, and Trino via `docker-compose.localaws.yml`
3. Wait for MiniStack's health endpoint
4. Run `ministack-init.sh` to create the Kinesis stream (`weather-stream`) and S3 input bucket (`data-pike-input`)
5. Wait for Trino to be query-ready
6. Create the Iceberg table (`weather_db.temperature_summary`) if it does not already exist
7. Submit the Flink job (mode = `LOCAL_AWS`)

### Iceberg table

The table is created automatically by `localaws-up.sh` on every run (idempotent). If you ever need to recreate it manually — for example after dropping it to reset local state — open a Trino shell:

```bash
./scripts/local-trino-shell.sh
```

Then run:

```sql
-- Reset (optional — drops table and schema)
DROP TABLE IF EXISTS iceberg.weather_db.temperature_summary;
DROP SCHEMA IF EXISTS iceberg.weather_db;

-- Create schema (required before table; location must match Flink's warehouse path)
CREATE SCHEMA IF NOT EXISTS iceberg.weather_db
WITH (location = 'file:///opt/flink/local-warehouse/weather_db');

-- Create table
CREATE TABLE IF NOT EXISTS iceberg.weather_db.temperature_summary (
    yyyy_mm_dd  VARCHAR,
    city_temps  MAP(VARCHAR, DOUBLE)
)
WITH (
    format         = 'AVRO',
    format_version = 2
);

-- Verify
DESCRIBE iceberg.weather_db.temperature_summary;
```

> **Note:** The Flink job calls `ensureTableExists()` at startup (when the Sink writer initializes) and will fail fast if the table is absent. Always ensure the table exists before submitting the job.

### Publish test data

Upload a sample file to MiniStack S3 and put the S3 Object Created notification directly into Kinesis. The publish scripts handle both steps:

```bash
./scripts/localaws-publish-json.sh
./scripts/localaws-publish-csv.sh
./scripts/localaws-publish-xml.sh
./scripts/localaws-publish-tsv.sh
```

Or use an arbitrary local file:

```bash
./scripts/localaws-publish-file.sh /path/to/your/weather_data.json
```

Alternatively, perform both steps manually:

```bash
# 1. Upload the file to MiniStack S3
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:4566 --region us-east-1 \
  s3 cp weather_data.json s3://data-pike-input/data/weather_data.json

# 2. Put the S3 Object Created notification into Kinesis
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  aws --endpoint-url http://localhost:4566 --region us-east-1 \
  kinesis put-record --stream-name weather-stream \
  --partition-key data/weather_data.json \
  --data "$(echo '{"source":"aws.s3","detail-type":"Object Created","detail":{"bucket":{"name":"data-pike-input"},"object":{"key":"data/weather_data.json"}}}' | base64 -w0)"
```

### Smoke test

```bash
./scripts/localaws-smoke-test.sh
```

Generates a unique payload, uploads it to MiniStack S3, and verifies that new Iceberg Avro files appear under `local-data/warehouse/` within 30 seconds.

### Query results

The same Trino query scripts work unchanged:

```bash
./scripts/local-trino-query.sh "SELECT * FROM iceberg.weather_db.temperature_summary ORDER BY yyyy_mm_dd LIMIT 20"
./scripts/local-trino-shell.sh
```

Flink UI: <http://localhost:8081>  
MiniStack console: <http://localhost:4566>  
Trino UI: <http://localhost:8080>

### Stop the stack

```bash
./scripts/localaws-down.sh
./scripts/localaws-down.sh --purge  # also removes local-data/
```

### How it works

```
Production:
  s3 cp → MiniStack S3 ──► EventBridge (automatic) ──► Kinesis ──► Flink

LOCAL_AWS mode (MiniStack):
  s3 cp → MiniStack S3                                             [needed by S3FileReader]
  kinesis put-record ──────────────────────────────► Kinesis ──► Flink
               ↑
       publish script does this step manually
```

#### Why the publish scripts write to both S3 and Kinesis

In production, uploading a file to S3 triggers **two independent downstream actions**:

1. **S3 stores the file** — `S3FileReader` later fetches the raw bytes from S3 using the bucket name and object key carried in the Kinesis record.
2. **S3 emits an `Object Created` event to EventBridge** — an EventBridge rule routes that event as a JSON record into the Kinesis stream, which is what Flink's `KinesisStreamsSource` actually reads. The record contains the bucket name and object key so the pipeline knows *what* to fetch.

These two concerns are intentionally decoupled: the Kinesis record is just a lightweight notification, not the file itself.

#### Why we bypass EventBridge in MiniStack

MiniStack fully emulates the AWS **control-plane API** for EventBridge (you can `put-rule`, `put-targets`, etc. and get back successful responses), but it does **not execute EventBridge target routing** at runtime — it accepts the configuration but never actually fires the rule or delivers records to Kinesis when an S3 event occurs. We discovered this empirically: the S3 upload succeeded, the bucket notification config was set, the rule and Kinesis target were registered, but `kinesis get-records` returned an empty shard every time.

Rather than work around this with a polling daemon or a Lambda shim, the publish scripts simply replicate the one step that MiniStack skips. After uploading to S3 they call `aws kinesis put-record` with the same `Object Created` JSON payload that EventBridge would have produced. Flink receives the identical record structure either way — the application code is completely unaware of how the record arrived in Kinesis.

#### Why `S3Client` works without code changes

`S3Client.create()` (AWS SDK v2) reads the `AWS_ENDPOINT_URL` environment variable automatically. The Flink containers have `AWS_ENDPOINT_URL=http://ministack:4566` injected via Docker Compose, so every `GetObject` call is silently redirected to MiniStack. The same JAR, with the same `S3FileReader` code, runs against real AWS in production and against MiniStack locally.

Path-style S3 access (`/bucket/key` instead of `bucket.hostname/key`) is enabled in `S3FileReader.open()` whenever `AWS_ENDPOINT_URL` is set. This is required because MiniStack (like LocalStack and most S3-compatible emulators) cannot serve virtual-hosted-style subdomain requests — DNS inside the Docker network has no wildcard entry for `bucket.ministack`.

#### Why Postgres runs as a separate container instead of using MiniStack RDS

MiniStack includes an RDS service, so it is reasonable to ask why the stack has a dedicated Postgres container. There are two reasons:

**MiniStack's RDS is a control-plane emulator, not a database engine.** It mimics the AWS RDS management API (`CreateDBInstance`, `DescribeDBInstances`, etc.) and returns successful responses, but it does not actually start or run a PostgreSQL process. There is no `jdbc:postgresql://ministack:5432/...` socket to connect to, so Iceberg's `JdbcCatalog` and Trino's JDBC metastore would have nothing to talk to.

**The local Postgres container is a stand-in for Glue, not for RDS.** In production the pipeline uses `GlueCatalog` — RDS is not involved at all. Locally, `JdbcCatalog` backed by Postgres provides the same catalog contract that `GlueCatalog` provides in production. Keeping the same Postgres container in both `LOCAL` and `LOCAL_AWS` modes means only one catalog implementation needs to be maintained and tested. Introducing a second catalog path just for `LOCAL_AWS` would add complexity with no benefit.

## Infrastructure

All Terraform configuration lives in the `terraform/` directory. See [terraform/README.md](terraform/README.md) for full deployment instructions, including state backend bootstrap, first-time JAR upload, and smoke testing.

## Deploying a New JAR Version

MSF pins the exact S3 object version of the JAR at deploy time. Uploading a new JAR to S3 alone is not enough — you must explicitly call `update-application` with the new `ObjectVersionId`:

```bash
# 1. Build and upload
mvn clean package -DskipTests
aws s3 cp target/data-pike-1.0-SNAPSHOT.jar s3://<jar-bucket>/jars/data-pike-1.0-SNAPSHOT.jar

# 2. Get the new S3 version ID
NEW_VER=$(aws s3api head-object \
  --bucket <jar-bucket> --key jars/data-pike-1.0-SNAPSHOT.jar \
  --query "VersionId" --output text)

# 3. Get the current application version
APP_VER=$(aws kinesisanalyticsv2 describe-application \
  --application-name <app-name> \
  --query "ApplicationDetail.ApplicationVersionId" --output text)

# 4. Update the application to pin the new JAR version
aws kinesisanalyticsv2 update-application \
  --application-name <app-name> \
  --current-application-version-id "$APP_VER" \
  --application-configuration-update \
  "{\"ApplicationCodeConfigurationUpdate\":{\"CodeContentTypeUpdate\":\"ZIPFILE\",\"CodeContentUpdate\":{\"S3ContentLocationUpdate\":{\"FileKeyUpdate\":\"jars/data-pike-1.0-SNAPSHOT.jar\",\"ObjectVersionUpdate\":\"$NEW_VER\"}}}}"

# 5. Start the application
aws kinesisanalyticsv2 start-application \
  --application-name <app-name> \
  --run-configuration '{}'
```

## Project Structure

```
src/main/java/org/muralis/datahose/
├── Application.java                  # Flink pipeline entry point
├── configuration/                    # AppConfigLoader — reads MSF/env/CLI config
├── model/                            # Data models (S3Notification, WeatherObservation, etc.)
├── processing/                       # Format detection, parsers, S3 file reading, summarization
├── sink/                             # IcebergSink — writes to Iceberg via Glue catalog
└── source/                           # KinesisMessageSource

terraform/
├── modules/
│   ├── flink/                        # Managed Flink application + IAM role + VPC config
│   ├── kinesis/                      # Kinesis Data Stream + EventBridge rule/target + IAM
│   ├── monitoring/                   # CloudWatch log group
│   ├── networking/                   # VPC, private subnets, security groups, VPC endpoints
│   └── storage/                      # KMS CMK, S3 buckets (input/iceberg/jar), Glue Catalog
└── scripts/                          # Bootstrap, deploy, and smoke test helpers
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
