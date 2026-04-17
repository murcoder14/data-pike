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
        RabbitMqConfig rabbitMq,
        IcebergSink.IcebergConfig iceberg) implements Serializable {

    public record KinesisConfig(
            String streamArn,
            String awsRegion,
            KinesisSourceConfigOptions.InitialPosition initialPosition) implements Serializable {
    }

    public record RabbitMqConfig(
            String host,
            int port,
            String username,
            String password,
            String virtualHost,
            String streamName,
            String consumerName,
            long pollTimeoutMs) implements Serializable {
    }
}
