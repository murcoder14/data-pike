package org.muralis.datahose.source;

import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.aws.config.AWSConfigOptions;
import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Factory for creating a configured Flink Kinesis source that consumes
 * raw JSON string messages from a Kinesis Data Stream.
 */
public final class KinesisMessageSource {

    private static final Logger LOG = LoggerFactory.getLogger(KinesisMessageSource.class);

    private KinesisMessageSource() {
        // Utility class — no instantiation
    }

    /**
     * Creates a {@link KinesisStreamsSource} configured to consume raw JSON strings
     * from the specified Kinesis stream.
     *
     * @param streamArn      the ARN of the Kinesis Data Stream to consume from
     * @param awsRegion      the AWS region where the stream resides
     * @param initialPosition the starting position: LATEST or TRIM_HORIZON
     * @return a configured {@code KinesisStreamsSource<String>}
     */
    public static KinesisStreamsSource<String> create(
            String streamArn,
            String awsRegion,
            KinesisSourceConfigOptions.InitialPosition initialPosition) {

        LOG.info("Creating Kinesis source for stream={}, region={}, initialPosition={}",
                streamArn, awsRegion, initialPosition);

        Configuration sourceConfig = new Configuration();
        sourceConfig.set(KinesisSourceConfigOptions.STREAM_INITIAL_POSITION, initialPosition);
        sourceConfig.set(AWSConfigOptions.AWS_REGION_OPTION, awsRegion);

        return KinesisStreamsSource.<String>builder()
                .setStreamArn(streamArn)
                .setSourceConfig(sourceConfig)
                .setDeserializationSchema(new SimpleStringSchema())
                .build();
    }

    /**
     * Convenience overload that defaults to {@code LATEST} starting position.
     *
     * @param streamArn the ARN of the Kinesis Data Stream
     * @param awsRegion the AWS region
     * @return a configured {@code KinesisStreamsSource<String>}
     */
    public static KinesisStreamsSource<String> create(String streamArn, String awsRegion) {
        return create(streamArn, awsRegion, KinesisSourceConfigOptions.InitialPosition.LATEST);
    }
}
