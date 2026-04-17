package org.muralis.datahose.configuration;

import org.apache.flink.util.ParameterTool;
import org.apache.flink.connector.kinesis.source.config.KinesisSourceConfigOptions;
import org.muralis.datahose.sink.IcebergSink;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;

/**
 * Loads mode-aware app configuration from environment, local properties files,
 * and Managed Flink runtime properties.
 */
public final class AppConfigLoader {

    private static final Logger LOG = LoggerFactory.getLogger(AppConfigLoader.class);

    private static final String DEFAULT_PROPERTIES_FILE = "application.properties";

    private AppConfigLoader() {
    }

    public static AppConfig load(String[] args) {
        Properties defaults = loadClasspathProperties(DEFAULT_PROPERTIES_FILE);
        ExecutionMode mode = resolveMode(args, defaults);

        if (mode == ExecutionMode.LOCAL) {
            return loadLocal(defaults);
        }
        return loadCloud(args, defaults);
    }

    private static AppConfig loadLocal(Properties defaults) {
        Properties local = merge(defaults, loadClasspathProperties("application-local.properties"));

        String host = getOptionalEnvOrProperty(local, "RABBITMQ_HOST", "rabbitmq.host", "localhost");
        int port = Integer.parseInt(getOptionalEnvOrProperty(local, "RABBITMQ_PORT", "rabbitmq.port", "5552"));
        String username = getOptionalEnvOrProperty(local, "RABBITMQ_USERNAME", "rabbitmq.username", "guest");
        String password = getOptionalEnvOrProperty(local, "RABBITMQ_PASSWORD", "rabbitmq.password", "guest");
        String virtualHost = getOptionalEnvOrProperty(local, "RABBITMQ_VHOST", "rabbitmq.virtual.host", "/");
        String streamName = getRequiredEnvOrProperty(local, "RABBITMQ_STREAM_NAME", "rabbitmq.stream.name");
        String consumerName = getOptionalEnvOrProperty(
            local, "RABBITMQ_CONSUMER_NAME", "rabbitmq.consumer.name", "data-pike-local-consumer");
        long pollTimeoutMs = Long.parseLong(getOptionalEnvOrProperty(
                local, "RABBITMQ_POLL_TIMEOUT_MS", "rabbitmq.poll.timeout.ms", "1000"));

        String warehousePath = getRequiredEnvOrProperty(local, "ICEBERG_WAREHOUSE_PATH", "iceberg.warehouse.path");
        String catalogName = getOptionalEnvOrProperty(local, "ICEBERG_CATALOG_NAME", "iceberg.catalog.name", "local_catalog");
        String tableName = getRequiredEnvOrProperty(local, "ICEBERG_TABLE_NAME", "iceberg.table.name");
        String jdbcUri = getOptionalEnvOrProperty(
            local, "ICEBERG_JDBC_URI", "iceberg.jdbc.uri",
            "jdbc:postgresql://localhost:5432/iceberg_catalog");
        String jdbcUser = getOptionalEnvOrProperty(
            local, "ICEBERG_JDBC_USER", "iceberg.jdbc.user", "iceberg_user");
        String jdbcPassword = getOptionalEnvOrProperty(
            local, "ICEBERG_JDBC_PASSWORD", "iceberg.jdbc.password", "iceberg_password");

        AppConfig.RabbitMqConfig rabbitMqConfig = new AppConfig.RabbitMqConfig(
            host, port, username, password, virtualHost, streamName, consumerName, pollTimeoutMs);

        AppConfig.KinesisConfig kinesisConfig = new AppConfig.KinesisConfig(
                "", "", KinesisSourceConfigOptions.InitialPosition.LATEST);

        IcebergSink.IcebergConfig icebergConfig = IcebergSink.IcebergConfig.localJdbc(
            warehousePath, catalogName, tableName, jdbcUri, jdbcUser, jdbcPassword);

        return new AppConfig(ExecutionMode.LOCAL, kinesisConfig, rabbitMqConfig, icebergConfig);
    }

    static AppConfig loadCloud(String[] args, Properties defaults) {
        Properties cloud = merge(defaults, loadClasspathProperties("application-cloud.properties"));

        // MSF injects runtime properties as --PropertyGroupId.key=value args
        ParameterTool params = ParameterTool.fromArgs(args);
        Map<String, Map<String, String>> appProperties = extractPropertyGroups(params);

        String streamArn;
        String awsRegion;
        String initialPosition = getOptionalEnvOrProperty(cloud,
                "KINESIS_INITIAL_POSITION", "kinesis.initial.position", "LATEST");

        String warehousePath;
        String catalogName;
        String tableName;

        if (appProperties.isEmpty()) {
            LOG.info("No runtime property groups found in args. Falling back to env/properties.");
            streamArn = getRequiredEnvOrProperty(cloud, "KINESIS_STREAM_ARN", "kinesis.stream.arn");
            awsRegion = getRequiredEnvOrProperty(cloud, "AWS_REGION", "kinesis.aws.region");
            warehousePath = getRequiredEnvOrProperty(cloud, "ICEBERG_WAREHOUSE_PATH", "iceberg.warehouse.path");
            catalogName = getRequiredEnvOrProperty(cloud, "ICEBERG_CATALOG_NAME", "iceberg.catalog.name");
            tableName = getRequiredEnvOrProperty(cloud, "ICEBERG_TABLE_NAME", "iceberg.table.name");
        } else {
            Map<String, String> kinesisProps = getPropertyGroup(appProperties, "KinesisSource");
            streamArn = getRequiredProperty(kinesisProps, "stream.arn");
            awsRegion = getRequiredProperty(kinesisProps, "aws.region");

            Map<String, String> icebergProps = getPropertyGroup(appProperties, "IcebergSink");
            warehousePath = getRequiredProperty(icebergProps, "warehouse.path");
            catalogName = getRequiredProperty(icebergProps, "catalog.name");
            tableName = getRequiredProperty(icebergProps, "table.name");
        }

        AppConfig.KinesisConfig kinesisConfig = new AppConfig.KinesisConfig(
                streamArn,
                awsRegion,
            KinesisSourceConfigOptions.InitialPosition.valueOf(initialPosition.toUpperCase(Locale.ROOT)));

        AppConfig.RabbitMqConfig rabbitMqConfig = new AppConfig.RabbitMqConfig(
            "", 5552, "", "", "/", "", "", 1000L);

        IcebergSink.IcebergConfig icebergConfig = new IcebergSink.IcebergConfig(
                warehousePath, catalogName, tableName);

        return new AppConfig(ExecutionMode.CLOUD, kinesisConfig, rabbitMqConfig, icebergConfig);
    }

    /**
     * Extracts property groups from ParameterTool args.
     * MSF injects runtime properties as --GroupId.key=value.
     * This method parses them into a Map of groupId → {key → value}.
     */
    static Map<String, Map<String, String>> extractPropertyGroups(ParameterTool params) {
        Map<String, Map<String, String>> groups = new HashMap<>();
        for (Map.Entry<String, String> entry : params.toMap().entrySet()) {
            String fullKey = entry.getKey();
            String value = entry.getValue();

            // ParameterTool treats --key=value as a key with no explicit value.
            // Normalize that form so Managed Flink style args work with either syntax.
            int equalsIndex = fullKey.indexOf('=');
            if (equalsIndex > 0) {
                value = fullKey.substring(equalsIndex + 1);
                fullKey = fullKey.substring(0, equalsIndex);
            }

            int dotIndex = fullKey.indexOf('.');
            if (dotIndex > 0 && dotIndex < fullKey.length() - 1) {
                String groupId = fullKey.substring(0, dotIndex);
                String propertyKey = fullKey.substring(dotIndex + 1);
                groups.computeIfAbsent(groupId, k -> new HashMap<>())
                      .put(propertyKey, value);
            }
        }
        if (!groups.isEmpty()) {
            LOG.info("Loaded {} runtime property groups from ParameterTool: {}",
                    groups.size(), groups.keySet());
        }
        return groups;
    }

    private static ExecutionMode resolveMode(String[] args, Properties defaults) {
        String argValue = null;
        for (String arg : args) {
            if ("local".equalsIgnoreCase(arg) || "cloud".equalsIgnoreCase(arg)
                    || "--local".equalsIgnoreCase(arg)
                    || arg.toLowerCase().startsWith("--mode=")) {
                argValue = arg;
                break;
            }
        }

        String envMode = System.getenv("EXECUTION_MODE");
        String configuredMode = defaults.getProperty("execution.mode", "cloud");

        if (argValue != null) {
            return ExecutionMode.fromString(argValue);
        }
        if (envMode != null && !envMode.isBlank()) {
            return ExecutionMode.fromString(envMode);
        }
        return ExecutionMode.fromString(configuredMode);
    }

    private static Properties loadClasspathProperties(String fileName) {
        Properties properties = new Properties();
        try (InputStream in = AppConfigLoader.class.getClassLoader().getResourceAsStream(fileName)) {
            if (in == null) {
                LOG.debug("Properties file '{}' not found on classpath", fileName);
                return properties;
            }
            properties.load(in);
            return properties;
        } catch (IOException e) {
            throw new IllegalStateException("Failed to load properties file: " + fileName, e);
        }
    }

    private static Properties merge(Properties base, Properties override) {
        Properties merged = new Properties();
        merged.putAll(base);
        for (String name : override.stringPropertyNames()) {
            String value = override.getProperty(name);
            if (value != null && !value.isBlank()) {
                merged.setProperty(name, value);
            }
        }
        return merged;
    }

    private static String getRequiredEnvOrProperty(Properties properties, String envKey, String propKey) {
        String env = System.getenv(envKey);
        if (env != null && !env.isBlank()) {
            return env;
        }

        String value = properties.getProperty(propKey);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required config: env '" + envKey
                    + "' or property '" + propKey + "'");
        }
        return value;
    }

    private static String getOptionalEnvOrProperty(Properties properties, String envKey, String propKey, String defaultValue) {
        String env = System.getenv(envKey);
        if (env != null && !env.isBlank()) {
            return env;
        }

        String value = properties.getProperty(propKey);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value;
    }

    private static Map<String, String> getPropertyGroup(Map<String, Map<String, String>> appProperties, String groupId) {
        Map<String, String> props = appProperties.get(groupId);
        if (props == null) {
            throw new IllegalStateException(
                    "Missing required property group '" + groupId + "' in Managed Flink environment_properties.");
        }
        return props;
    }

    private static String getRequiredProperty(Map<String, String> props, String key) {
        String value = props.get(key);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "Missing required property '" + key + "' in Managed Flink environment_properties.");
        }
        return value;
    }
}
