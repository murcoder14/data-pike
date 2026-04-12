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
