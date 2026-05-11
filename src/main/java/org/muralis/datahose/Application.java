package org.muralis.datahose;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.configuration.AppConfig;
import org.muralis.datahose.configuration.AppConfigLoader;
import org.muralis.datahose.processing.FileProcessor;
import org.muralis.datahose.processing.MessageParser;
import org.muralis.datahose.processing.S3FileReader;
import org.muralis.datahose.sink.IcebergSink;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.typeinfo.TypeInformation;
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
 * <p>Reads mode-aware configuration (local or cloud), configures checkpointing,
 * and wires the pipeline:
 * <ol>
 *   <li>KinesisMessageSource → DataStream&lt;String&gt;</li>
 *   <li>MessageParser → DataStream&lt;S3Notification&gt;</li>
 *   <li>S3FileReader → DataStream&lt;S3FileContent&gt;</li>
 *   <li>FileProcessor → DataStream&lt;ProcessedRecord&gt;</li>
 *   <li>IcebergSink (write to Iceberg tables)</li>
 * </ol>
 */
public class Application {

    private static final Logger LOG = LoggerFactory.getLogger(Application.class);

    static final long CHECKPOINT_INTERVAL_MS = 60_000L;

    public static void main(String[] args) throws Exception {
        try {
            run(args);
        } catch (Throwable t) {
            // Print the full cause chain to stderr — captured by MSF Job Manager logs
            // even before CloudWatch logging is bootstrapped.
            System.err.println("=== FATAL STARTUP ERROR ===");
            t.printStackTrace(System.err);
            System.err.flush();
            throw t;
        }
    }

    static void run(String[] args) throws Exception {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // MSF runtime properties are read from /etc/flink/application_properties.json
        // inside AppConfigLoader.loadCloud() via readApplicationPropertiesFile().
        AppConfig config = AppConfigLoader.load(args);

        LOG.info("Starting Flink Data Pipeline in {} mode", config.mode());

        // --- Checkpointing for fault tolerance ---
        env.enableCheckpointing(CHECKPOINT_INTERVAL_MS, CheckpointingMode.EXACTLY_ONCE);

        // --- Wire the pipeline ---

        // 1. Kinesis source → DataStream<String>
        DataStream<String> rawMessages = buildInputSource(env, config);

        // 2/3. Build file contents stream via mode-specific path.
        DataStream<S3FileContent> fileContents = buildFileContents(rawMessages, config);

        // 4. FileProcessor → DataStream<ProcessedRecord>
        DataStream<ProcessedRecord> processedRecords = fileContents
                .flatMap(new FileProcessor())
                .name("FileProcessor");

        // 5. IcebergSink — write processed records to Iceberg tables
        processedRecords
                .sinkTo(new IcebergSink(config.iceberg()))
                .name("IcebergSink");

        // --- Execute ---
        env.execute("Flink Data Pipeline");
    }

    static DataStream<String> buildInputSource(StreamExecutionEnvironment env, AppConfig config) {
        // LOCAL_AWS and CLOUD both use the Kinesis connector.
        // In LOCAL_AWS mode, KinesisConfig.endpointUrl() is set to the MiniStack endpoint.
        KinesisStreamsSource<String> kinesisSource = KinesisMessageSource.create(config.kinesis());

        return env.fromSource(
                kinesisSource,
                WatermarkStrategy.noWatermarks(),
                "KinesisSource",
                TypeInformation.of(String.class));
    }

    static DataStream<S3FileContent> buildFileContents(DataStream<String> rawMessages, AppConfig config) {
        // LOCAL_AWS and CLOUD: full S3 path. In LOCAL_AWS mode, S3Client.create() picks up
        // AWS_ENDPOINT_URL from the container environment to point at MiniStack.
        DataStream<S3Notification> notifications = rawMessages
                .flatMap(new MessageParser())
                .name("MessageParser");

        return notifications
                .flatMap(new S3FileReader())
                .name("S3FileReader");
    }
}
