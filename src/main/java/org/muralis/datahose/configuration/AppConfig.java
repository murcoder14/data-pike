package org.muralis.datahose.configuration;

import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.muralis.datahose.sink.IcebergSink;

import java.io.Serializable;

/**
 * Runtime application configuration after mode-aware resolution.
 */
public record AppConfig(
        ExecutionMode mode,
        KinesisConfig kinesis,
        IcebergSink.IcebergConfig iceberg) implements Serializable {

    public record KinesisConfig(
            String streamArn,
            String awsRegion,
            KinesisSourceConfigOptions.InitialPosition initialPosition,
            String endpointUrl) implements Serializable {

        /** Convenience constructor for production/cloud use (no endpoint override). */
        public KinesisConfig(String streamArn, String awsRegion,
                             KinesisSourceConfigOptions.InitialPosition initialPosition) {
            this(streamArn, awsRegion, initialPosition, null);
        }
    }

}
