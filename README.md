# Data Pike

A streaming data pipeline built with Apache Flink on AWS Managed Service for Apache Flink. Ingests files from S3 in multiple formats (JSON, XML, delimited), processes weather observation data, computes temperature summaries, and writes output to Apache Iceberg tables.

## Architecture

```
S3 (file upload) → EventBridge → Kinesis Data Stream → Apache Flink → Iceberg (via Glue Catalog)
```

1. Files land in an S3 input bucket
2. EventBridge captures `Object Created` events and routes them to Kinesis
3. Flink consumes notifications from Kinesis, reads the files from S3, detects the format, and parses them
4. Processed records are written to Apache Iceberg tables backed by S3 and cataloged in AWS Glue

## Supported File Formats

- JSON
- XML
- Delimited (CSV, TSV, pipe-separated, etc.)

## Tech Stack

- Java 17
- Apache Flink 2.2.0
- Apache Iceberg 1.10.1
- Apache Avro 1.12.1
- Jackson 2.21.2
- AWS SDK (Kinesis Analytics V2, S3)
- Terraform (infrastructure as code)
- CodePipeline / CodeBuild (CI/CD)

## Prerequisites

- Java 17+
- Maven 3.8+
- AWS CLI configured with appropriate credentials
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

Managed Flink must provide two environment property groups:

- `KinesisSource`
	- `stream.arn`
	- `aws.region`
- `IcebergSink`
	- `warehouse.path`
	- `catalog.name`
	- `table.name`

If those property groups are absent, the application falls back to standard environment variables or classpath properties:

```bash
KINESIS_STREAM_ARN
AWS_REGION
ICEBERG_WAREHOUSE_PATH
ICEBERG_CATALOG_NAME
ICEBERG_TABLE_NAME
KINESIS_INITIAL_POSITION
```

## Local Mode (RabbitMQ Streams + Local Iceberg)

Trino compatibility note:
local mode uses an Iceberg JDBC catalog backed by PostgreSQL.
Docker Compose starts Postgres and both Flink and Trino connect to it
for Iceberg metadata, while table data stays in the local warehouse path.
Host-side defaults in application-local.properties point at the compose-exposed
Postgres port 5433; in-container services override that with port 5432.

Run preflight checks (tools, Docker daemon, and ports):

```bash
./scripts/local-preflight.sh
```

Create your local environment file for credentials and runtime overrides:

```bash
cp .env.local.example .env.local
```

Edit `.env.local` as needed for your local RabbitMQ/Postgres credentials.

Start local stack and submit Flink job:

```bash
./scripts/local-up.sh
```

Send test messages and verify Iceberg output:

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

All Terraform configuration lives in the `terraform/` directory. See [terraform/README.md](terraform/README.md) for detailed deployment instructions, including state backend bootstrap, multi-environment setup, and smoke testing.

## Project Structure

```
src/main/java/org/muralis/datahose/
├── Application.java                  # Flink pipeline entry point
├── model/                            # Data models (S3Notification, WeatherObservation, etc.)
├── processing/                       # Parsers, format detection, file reading, summarization
├── sink/                             # Iceberg sink
└── source/                           # Kinesis message source

terraform/
├── modules/
│   ├── cicd/                         # CodeBuild + CodePipeline
│   ├── flink/                        # Managed Flink application + IAM
│   ├── kinesis/                      # Kinesis Data Stream + EventBridge
│   ├── monitoring/                   # CloudWatch log groups
│   ├── networking/                   # VPC, subnets, security groups, endpoints
│   └── storage/                      # KMS, S3 buckets, Glue Catalog
└── scripts/                          # Bootstrap and deployment helpers
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
