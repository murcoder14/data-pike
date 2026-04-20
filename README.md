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

## Local Mode (RabbitMQ Streams + Local Iceberg)

Local mode replaces Kinesis with RabbitMQ Streams as the source and uses an Iceberg JDBC catalog backed by PostgreSQL. Docker Compose starts all required services. Trino connects to the same catalog for ad-hoc queries.

Run preflight checks (tools, Docker daemon, ports):

```bash
./scripts/local-preflight.sh
```

Start the local stack and submit the Flink job:

```bash
./scripts/local-up.sh
```

Publish test files to RabbitMQ:

```bash
./scripts/local-publish-json.sh
./scripts/local-publish-xml.sh
./scripts/local-publish-csv.sh
./scripts/local-publish-tsv.sh
```

Run the full smoke test (publishes files and verifies Iceberg output):

```bash
./scripts/local-smoke-test.sh
```

Query Iceberg tables with Trino:

```bash
./scripts/local-trino-query.sh "SHOW TABLES IN iceberg.default"
./scripts/local-trino-query.sh "SELECT * FROM iceberg.default.temperature_summary ORDER BY date LIMIT 20"
```

Open interactive Trino shell:

```bash
./scripts/local-trino-shell.sh
```

Collect service logs into timestamped files:

```bash
./scripts/local-logs.sh
```

Stop local stack:

```bash
./scripts/local-down.sh
```

Stop and purge local data:

```bash
./scripts/local-down.sh --purge
```

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
└── source/                           # KinesisMessageSource, RabbitMqStreamsSourceFunction

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
