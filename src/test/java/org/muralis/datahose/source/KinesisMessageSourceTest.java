package org.muralis.datahose.source;

import org.apache.flink.connector.kinesis.source.KinesisStreamsSource;
import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Unit tests for {@link KinesisMessageSource}.
 */
class KinesisMessageSourceTest {

    private static final String STREAM_ARN =
            "arn:aws:kinesis:us-east-1:123456789012:stream/test-stream";
    private static final String REGION = "us-east-1";

    @Test
    void createWithExplicitPosition_returnsNonNullSource() {
        KinesisStreamsSource<String> source = KinesisMessageSource.create(
                STREAM_ARN, REGION, KinesisSourceConfigOptions.InitialPosition.TRIM_HORIZON);
        assertNotNull(source, "Source should not be null");
    }

    @Test
    void createWithDefaultPosition_returnsNonNullSource() {
        KinesisStreamsSource<String> source = KinesisMessageSource.create(STREAM_ARN, REGION);
        assertNotNull(source, "Source should not be null when using default position");
    }

    @Test
    void createWithLatestPosition_returnsNonNullSource() {
        KinesisStreamsSource<String> source = KinesisMessageSource.create(
                STREAM_ARN, REGION, KinesisSourceConfigOptions.InitialPosition.LATEST);
        assertNotNull(source, "Source should not be null for LATEST position");
    }
}
