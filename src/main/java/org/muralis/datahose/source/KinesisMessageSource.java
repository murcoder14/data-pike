package org.muralis.datahose.source;

import org.muralis.datahose.configuration.AppConfig;
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
     * @param streamArn       the ARN of the Kinesis Data Stream to consume from
     * @param awsRegion       the AWS region where the stream resides
     * @param initialPosition the starting position: LATEST or TRIM_HORIZON
     * @return a configured {@code KinesisStreamsSource<String>}
     */
    public static KinesisStreamsSource<String> create(
            String streamArn,
            String awsRegion,
            KinesisSourceConfigOptions.InitialPosition initialPosition) {
        return create(streamArn, awsRegion, initialPosition, null);
    }

    /**
     * Creates a {@link KinesisStreamsSource} with an optional custom AWS endpoint URL.
     * When {@code endpointUrl} is non-null, all Kinesis API calls are directed to that
     * endpoint (e.g. {@code http://localhost:4566} for MiniStack).
     *
     * @param streamArn       the ARN of the Kinesis Data Stream to consume from
     * @param awsRegion       the AWS region where the stream resides
     * @param initialPosition the starting position: LATEST or TRIM_HORIZON
     * @param endpointUrl     custom AWS endpoint URL, or {@code null} for real AWS
     * @return a configured {@code KinesisStreamsSource<String>}
     */
    public static KinesisStreamsSource<String> create(
            String streamArn,
            String awsRegion,
            KinesisSourceConfigOptions.InitialPosition initialPosition,
            String endpointUrl) {

        LOG.info("Creating Kinesis source for stream={}, region={}, initialPosition={}, endpoint={}",
                streamArn, awsRegion, initialPosition,
                endpointUrl != null ? endpointUrl : "real AWS");

        Configuration sourceConfig = new Configuration();
        sourceConfig.set(KinesisSourceConfigOptions.STREAM_INITIAL_POSITION, initialPosition);
        sourceConfig.set(AWSConfigOptions.AWS_REGION_OPTION, awsRegion);

        if (endpointUrl != null && !endpointUrl.isBlank()) {
            sourceConfig.set(AWSConfigOptions.AWS_ENDPOINT_OPTION, endpointUrl);
        }

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
        return create(streamArn, awsRegion, KinesisSourceConfigOptions.InitialPosition.LATEST, null);
    }

    /**
     * Creates a source from resolved configuration, honouring any endpoint URL override
     * set in {@link AppConfig.KinesisConfig#endpointUrl()} for local-AWS mode.
     */
    public static KinesisStreamsSource<String> create(AppConfig.KinesisConfig config) {
        return create(config.streamArn(), config.awsRegion(), config.initialPosition(), config.endpointUrl());
    }
}
