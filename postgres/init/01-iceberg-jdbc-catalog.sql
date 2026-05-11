-- Initialise the Iceberg JDBC catalog schema (V1).
-- Both Flink's JdbcCatalog and Trino's TrinoJdbcCatalogFactory require these
-- two tables to exist before any catalog operation.  Creating them here (via
-- Postgres docker-entrypoint-initdb.d) avoids the race where Trino connects
-- before the schema has been bootstrapped and gets "relation iceberg_tables
-- does not exist" inside updateSchemaIfRequired().

CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name               VARCHAR(255) NOT NULL,
    table_namespace            VARCHAR(255) NOT NULL,
    table_name                 VARCHAR(255) NOT NULL,
    metadata_location          VARCHAR(1000),
    previous_metadata_location VARCHAR(1000),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);

CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name   VARCHAR(255) NOT NULL,
    namespace      VARCHAR(255) NOT NULL,
    property_key   VARCHAR(5500),
    property_value VARCHAR(1000),
    UNIQUE (catalog_name, namespace, property_key)
);
