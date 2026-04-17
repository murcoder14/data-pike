package org.muralis.datahose;

import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.junit.jupiter.api.Test;
import org.muralis.datahose.configuration.AppConfig;
import org.muralis.datahose.configuration.ExecutionMode;
import org.muralis.datahose.sink.IcebergSink;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class ApplicationTest {

    @Test
    void buildInputSource_localModeUsesSingleParallelism() {
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        AppConfig config = new AppConfig(
                ExecutionMode.LOCAL,
                new AppConfig.KinesisConfig("", "", KinesisSourceConfigOptions.InitialPosition.LATEST),
                new AppConfig.RabbitMqConfig(
                        "localhost",
                        5552,
                        "guest",
                        "guest",
                        "/",
                        "weather-stream",
                        "data-pike-local-consumer",
                        1000L),
                IcebergSink.IcebergConfig.localJdbc(
                        "file:///tmp/warehouse",
                        "local_catalog",
                        "default.temperature_summary",
                        "jdbc:postgresql://localhost:5433/iceberg_catalog",
                        "iceberg_user",
                        "iceberg_password"));

        DataStream<String> source = Application.buildInputSource(env, config);

        assertNotNull(source);
        assertEquals(1, source.getParallelism());
    }
}