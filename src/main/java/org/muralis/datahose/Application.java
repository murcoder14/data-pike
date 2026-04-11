package org.muralis.datahose;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.processing.FileProcessor;
import org.muralis.datahose.processing.MessageParser;
import org.muralis.datahose.processing.S3FileReader;
import org.muralis.datahose.sink.IcebergSink;
import org.muralis.datahose.sink.TransactionLogger;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.core.execution.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.muralis.datahose.source.KinesisMessageSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Entry point for the Flink streaming data pipeline.
 *
 * <p>Sets up the {@link StreamExecutionEnvironment}, configures checkpointing for
 * fault tolerance, reads configuration from environment variables, and wires the
 * full pipeline:
 * <ol>
 *   <li>KinesisMessageSource → DataStream&lt;String&gt;</li>
 *   <li>MessageParser → DataStream&lt;S3Notification&gt;</li>
 *   <li>S3FileReader → DataStream&lt;S3FileContent&gt;</li>
 *   <li>FileProcessor → DataStream&lt;ProcessedRecord&gt;</li>
 *   <li>IcebergSink (write to Iceberg tables)</li>
 *   <li>TransactionLogger (log transactions to RDS PostgreSQL)</li>
 * </ol>
 */
public class Application {

    private static final Logger LOG = LoggerFactory.getLogger(Application.class);

    static final long CHECKPOINT_INTERVAL_MS = 60_000L;

    public static void main(String[] args) throws Exception {
        // --- Configuration from environment variables ---
        String kinesisStreamArn = getRequiredEnv("KINESIS_STREAM_ARN");
        String awsRegion = getRequiredEnv("AWS_REGION");
        String icebergWarehousePath = getRequiredEnv("ICEBERG_WAREHOUSE_PATH");
        String icebergCatalogName = getRequiredEnv("ICEBERG_CATALOG_NAME");
        String icebergTableName = getRequiredEnv("ICEBERG_TABLE_NAME");
        String jdbcUrl = getRequiredEnv("JDBC_URL");
        String dbUsername = getRequiredEnv("DB_USERNAME");
        String dbPassword = getRequiredEnv("DB_PASSWORD");

        LOG.info("Starting Flink Data Pipeline: stream={}, region={}, icebergTable={}.{}.{}",
                kinesisStreamArn, awsRegion, icebergCatalogName, icebergWarehousePath, icebergTableName);

        // --- StreamExecutionEnvironment ---
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // --- Checkpointing for fault tolerance ---
        env.enableCheckpointing(CHECKPOINT_INTERVAL_MS, CheckpointingMode.EXACTLY_ONCE);

        // --- Build sink configurations ---
        IcebergSink.IcebergConfig icebergConfig = new IcebergSink.IcebergConfig(
                icebergWarehousePath, icebergCatalogName, icebergTableName);

        TransactionLogger.JdbcConfig jdbcConfig = new TransactionLogger.JdbcConfig(
                jdbcUrl, dbUsername, dbPassword, icebergTableName);

        // --- Wire the pipeline ---

        // 1. Kinesis source → DataStream<String>
        KinesisStreamsSource<String> kinesisSource = KinesisMessageSource.create(kinesisStreamArn, awsRegion);
        DataStream<String> rawMessages = env.fromSource(
                kinesisSource, WatermarkStrategy.noWatermarks(), "KinesisSource");

        // 2. MessageParser → DataStream<S3Notification>
        DataStream<S3Notification> notifications = rawMessages
                .flatMap(new MessageParser())
                .name("MessageParser");

        // 3. S3FileReader → DataStream<S3FileContent>
        DataStream<S3FileContent> fileContents = notifications
                .flatMap(new S3FileReader())
                .name("S3FileReader");

        // 4. FileProcessor → DataStream<ProcessedRecord>
        DataStream<ProcessedRecord> processedRecords = fileContents
                .flatMap(new FileProcessor())
                .name("FileProcessor");

        // 5. IcebergSink — write processed records to Iceberg tables
        processedRecords
                .sinkTo(new IcebergSink(icebergConfig))
                .name("IcebergSink");

        // 6. TransactionLogger — log transaction details to RDS PostgreSQL
        processedRecords
                .sinkTo(new TransactionLogger(jdbcConfig))
                .name("TransactionLogger");

        // --- Execute ---
        env.execute("Flink Data Pipeline");
    }

    /**
     * Reads a required environment variable. Throws {@link IllegalStateException}
     * if the variable is not set or is blank.
     */
    static String getRequiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "Required environment variable '" + name + "' is not set or is blank");
        }
        return value;
    }
}
