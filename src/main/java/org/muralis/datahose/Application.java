package org.muralis.datahose;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.processing.FileProcessor;
import org.muralis.datahose.processing.MessageParser;
import org.muralis.datahose.processing.S3FileReader;
import org.muralis.datahose.sink.IcebergSink;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.core.execution.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.muralis.datahose.source.KinesisMessageSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.kinesisanalyticsv2.KinesisAnalyticsV2Client;
import software.amazon.awssdk.services.kinesisanalyticsv2.model.DescribeApplicationRequest;
import software.amazon.awssdk.services.kinesisanalyticsv2.model.DescribeApplicationResponse;
import software.amazon.awssdk.services.kinesisanalyticsv2.model.PropertyGroup;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Entry point for the Flink streaming data pipeline.
 *
 * <p>Reads configuration from Managed Flink runtime properties via the
 * KinesisAnalyticsV2 DescribeApplication API, configures checkpointing,
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
        // --- Read runtime properties from Managed Flink environment ---
        Map<String, Map<String, String>> appProperties = getApplicationProperties();

        Map<String, String> kinesisProps = getPropertyGroup(appProperties, "KinesisSource");
        String kinesisStreamArn = getRequiredProperty(kinesisProps, "stream.arn");
        String awsRegion = getRequiredProperty(kinesisProps, "aws.region");

        Map<String, String> icebergProps = getPropertyGroup(appProperties, "IcebergSink");
        String icebergWarehousePath = getRequiredProperty(icebergProps, "warehouse.path");
        String icebergCatalogName = getRequiredProperty(icebergProps, "catalog.name");
        String icebergTableName = getRequiredProperty(icebergProps, "table.name");

        LOG.info("Starting Flink Data Pipeline: stream={}, region={}, iceberg={}/{}/{}",
                kinesisStreamArn, awsRegion, icebergCatalogName, icebergWarehousePath, icebergTableName);

        // --- StreamExecutionEnvironment ---
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        // --- Checkpointing for fault tolerance ---
        env.enableCheckpointing(CHECKPOINT_INTERVAL_MS, CheckpointingMode.EXACTLY_ONCE);

        // --- Build sink configurations ---
        IcebergSink.IcebergConfig icebergConfig = new IcebergSink.IcebergConfig(
                icebergWarehousePath, icebergCatalogName, icebergTableName);

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

        // --- Execute ---
        env.execute("Flink Data Pipeline");
    }

    /**
     * Fetches application runtime properties from the Managed Flink service
     * using the KinesisAnalyticsV2 DescribeApplication API.
     *
     * <p>The application name is read from the {@code APPLICATION_NAME}
     * environment variable, which is automatically set by Managed Flink.
     *
     * @return map of property group ID to property key-value pairs
     */
    static Map<String, Map<String, String>> getApplicationProperties() {
        String appName = System.getenv("APPLICATION_NAME");
        if (appName == null || appName.isBlank()) {
            LOG.warn("APPLICATION_NAME not set (local mode). Using empty properties.");
            return Map.of();
        }

        LOG.info("Fetching runtime properties for application: {}", appName);

        try (KinesisAnalyticsV2Client client = KinesisAnalyticsV2Client.create()) {
            DescribeApplicationResponse response = client.describeApplication(
                    DescribeApplicationRequest.builder()
                            .applicationName(appName)
                            .build());

            List<PropertyGroup> groups = response.applicationDetail()
                    .applicationConfigurationDescription()
                    .environmentPropertyDescriptions()
                    .propertyGroupDescriptions();

            Map<String, Map<String, String>> result = new HashMap<>();
            for (PropertyGroup group : groups) {
                result.put(group.propertyGroupId(), group.propertyMap());
                LOG.info("Loaded property group '{}' with {} properties",
                        group.propertyGroupId(), group.propertyMap().size());
            }
            return result;
        }
    }

    /**
     * Gets a property group by ID, throwing if not found.
     */
    static Map<String, String> getPropertyGroup(Map<String, Map<String, String>> appProperties, String groupId) {
        Map<String, String> props = appProperties.get(groupId);
        if (props == null) {
            throw new IllegalStateException(
                    "Missing required property group '" + groupId + "'. "
                    + "Configure it in the Flink application's environment_properties.");
        }
        return props;
    }

    /**
     * Gets a required property value, throwing if missing or blank.
     */
    static String getRequiredProperty(Map<String, String> props, String key) {
        String value = props.get(key);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "Missing required property '" + key + "'. "
                    + "Configure it in the Flink application's environment_properties.");
        }
        return value;
    }
}
