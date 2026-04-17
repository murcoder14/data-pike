package org.muralis.datahose;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.configuration.AppConfig;
import org.muralis.datahose.configuration.AppConfigLoader;
import org.muralis.datahose.configuration.ExecutionMode;
import org.muralis.datahose.processing.FileProcessor;
import org.muralis.datahose.processing.MessageParser;
import org.muralis.datahose.processing.RabbitMessageFileContentAdapter;
import org.muralis.datahose.processing.S3FileReader;
import org.muralis.datahose.sink.IcebergSink;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.core.execution.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.muralis.datahose.source.KinesisMessageSource;
import org.muralis.datahose.source.RabbitMqStreamsSourceFunction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Entry point for the Flink streaming data pipeline.
 *
 * <p>Reads mode-aware configuration (local or cloud), configures checkpointing,
 * and wires the pipeline:
 * <ol>
 *   <li>KinesisMessageSource or RabbitMQ Streams source → DataStream&lt;String&gt;</li>
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
        AppConfig config = AppConfigLoader.load(args);

        LOG.info("Starting Flink Data Pipeline in {} mode", config.mode());

        // --- StreamExecutionEnvironment ---
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // --- Checkpointing for fault tolerance ---
        env.enableCheckpointing(CHECKPOINT_INTERVAL_MS, CheckpointingMode.EXACTLY_ONCE);

        // --- Wire the pipeline ---

        // 1. Kinesis or RabbitMQ source → DataStream<String>
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
                if (config.mode() == ExecutionMode.LOCAL) {
                        return env.addSource(new RabbitMqStreamsSourceFunction(config.rabbitMq()))
                                        .setParallelism(1)
                                        .name("RabbitMqStreamsSource");
                }

                KinesisStreamsSource<String> kinesisSource = KinesisMessageSource.create(
                                config.kinesis().streamArn(),
                                config.kinesis().awsRegion(),
                                config.kinesis().initialPosition());

                return env.fromSource(
                                kinesisSource,
                                WatermarkStrategy.noWatermarks(),
                                "KinesisSource");
    }

        static DataStream<S3FileContent> buildFileContents(DataStream<String> rawMessages, AppConfig config) {
                if (config.mode() == ExecutionMode.LOCAL) {
                        return rawMessages
                                        .flatMap(new RabbitMessageFileContentAdapter(config.rabbitMq().streamName()))
                                        .name("RabbitMessageFileContentAdapter");
                }

                DataStream<S3Notification> notifications = rawMessages
                                .flatMap(new MessageParser())
                                .name("MessageParser");

                return notifications
                                .flatMap(new S3FileReader())
                                .name("S3FileReader");
        }
}
