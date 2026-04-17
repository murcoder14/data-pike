package org.muralis.datahose.configuration;

import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.apache.flink.util.ParameterTool;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.assertEquals;

class AppConfigLoaderTest {

    @Test
    void extractPropertyGroups_parsesManagedFlinkArgs() {
        ParameterTool params = ParameterTool.fromArgs(new String[] {
                "--KinesisSource.stream.arn=arn:aws:kinesis:us-east-1:123456789012:stream/weather",
                "--KinesisSource.aws.region=us-east-1",
                "--IcebergSink.warehouse.path=s3://warehouse/path",
                "--IcebergSink.catalog.name=glue_catalog",
                "--IcebergSink.table.name=default.temperature_summary"
        });

        Map<String, Map<String, String>> groups = AppConfigLoader.extractPropertyGroups(params);

        assertEquals(2, groups.size());
        assertEquals("arn:aws:kinesis:us-east-1:123456789012:stream/weather",
                groups.get("KinesisSource").get("stream.arn"));
        assertEquals("us-east-1", groups.get("KinesisSource").get("aws.region"));
        assertEquals("s3://warehouse/path", groups.get("IcebergSink").get("warehouse.path"));
        assertEquals("glue_catalog", groups.get("IcebergSink").get("catalog.name"));
        assertEquals("default.temperature_summary", groups.get("IcebergSink").get("table.name"));
    }

    @Test
    void loadCloud_usesManagedFlinkPropertyGroups() {
        Properties defaults = new Properties();
        defaults.setProperty("kinesis.initial.position", "TRIM_HORIZON");

        AppConfig config = AppConfigLoader.loadCloud(new String[] {
                "--KinesisSource.stream.arn=arn:aws:kinesis:us-east-1:123456789012:stream/weather",
                "--KinesisSource.aws.region=us-east-1",
                "--IcebergSink.warehouse.path=s3://warehouse/path",
                "--IcebergSink.catalog.name=glue_catalog",
                "--IcebergSink.table.name=default.temperature_summary"
        }, defaults);

        assertEquals(ExecutionMode.CLOUD, config.mode());
        assertEquals("arn:aws:kinesis:us-east-1:123456789012:stream/weather", config.kinesis().streamArn());
        assertEquals("us-east-1", config.kinesis().awsRegion());
        assertEquals(KinesisSourceConfigOptions.InitialPosition.LATEST, config.kinesis().initialPosition());
        assertEquals("s3://warehouse/path", config.iceberg().warehousePath());
        assertEquals("glue_catalog", config.iceberg().catalogName());
        assertEquals("default.temperature_summary", config.iceberg().tableName());
    }

    @Test
    void loadCloud_fallsBackToProvidedPropertiesWhenGroupsAbsent() {
        Properties defaults = new Properties();
        defaults.setProperty("kinesis.stream.arn", "arn:aws:kinesis:us-east-1:123456789012:stream/fallback");
        defaults.setProperty("kinesis.aws.region", "us-east-1");
        defaults.setProperty("kinesis.initial.position", "LATEST");
        defaults.setProperty("iceberg.warehouse.path", "s3://fallback-warehouse/path");
        defaults.setProperty("iceberg.catalog.name", "fallback_catalog");
        defaults.setProperty("iceberg.table.name", "default.fallback_table");

        AppConfig config = AppConfigLoader.loadCloud(new String[0], defaults);

        assertEquals(ExecutionMode.CLOUD, config.mode());
        assertEquals("arn:aws:kinesis:us-east-1:123456789012:stream/fallback", config.kinesis().streamArn());
        assertEquals("us-east-1", config.kinesis().awsRegion());
        assertEquals(KinesisSourceConfigOptions.InitialPosition.LATEST, config.kinesis().initialPosition());
        assertEquals("s3://fallback-warehouse/path", config.iceberg().warehousePath());
        assertEquals("fallback_catalog", config.iceberg().catalogName());
        assertEquals("default.fallback_table", config.iceberg().tableName());
    }
}