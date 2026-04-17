package org.muralis.datahose.sink;

import org.apache.avro.generic.GenericRecord;
import org.apache.hadoop.conf.Configuration;
import org.apache.iceberg.CatalogProperties;
import org.apache.iceberg.CatalogUtil;
import org.apache.iceberg.DataFile;
import org.apache.iceberg.DataFiles;
import org.apache.iceberg.FileFormat;
import org.apache.iceberg.PartitionSpec;
import org.apache.iceberg.Schema;
import org.apache.iceberg.Table;
import org.apache.iceberg.hadoop.HadoopFileIO;
import org.apache.iceberg.aws.glue.GlueCatalog;
import org.apache.iceberg.aws.s3.S3FileIO;
import org.apache.iceberg.catalog.Catalog;
import org.apache.iceberg.catalog.Namespace;
import org.apache.iceberg.catalog.SupportsNamespaces;
import org.apache.iceberg.catalog.TableIdentifier;
import org.apache.iceberg.data.GenericAppenderFactory;
import org.apache.iceberg.data.IcebergGenerics;
import org.apache.iceberg.exceptions.AlreadyExistsException;
import org.apache.iceberg.exceptions.NoSuchTableException;
import org.apache.iceberg.io.CloseableIterable;
import org.apache.iceberg.io.FileAppender;
import org.apache.iceberg.io.OutputFile;
import org.apache.iceberg.types.Types;
import org.apache.iceberg.hadoop.HadoopCatalog;
import org.jetbrains.annotations.NotNull;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.TemperatureSummary;
import org.muralis.datahose.processing.TemperatureSummaryAvroMapper;
import org.apache.flink.api.connector.sink2.Sink;
import org.apache.flink.api.connector.sink2.SinkWriter;
import org.apache.flink.api.connector.sink2.WriterInitContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.Serial;
import java.io.Serializable;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Flink Sink V2 implementation that writes processed records to Apache Iceberg tables
 * in the Iceberg output bucket.
 *
 * <p>Records with {@link ProcessedRecord#STATUS_FAILURE} status are skipped since they
 * carry no data rows. Write failures are retried with exponential backoff
 * (3 attempts, 1s/2s/4s).
 */
public class IcebergSink implements Sink<ProcessedRecord> {

    @Serial
    private static final long serialVersionUID = 1L;
    private static final String JDBC_CATALOG_IMPL = "org.apache.iceberg.jdbc.JdbcCatalog";

    private final IcebergConfig config;
    private final IcebergWriterFactory writerFactory;

    /**
     * Creates an IcebergSink with the given catalog configuration.
     *
     * @param config Iceberg catalog configuration (warehouse path, catalog name, table name)
     */
    public IcebergSink(IcebergConfig config) {
        this(config, DefaultIcebergTableWriter::new);
    }

    /**
     * Constructor accepting a custom writer factory (for testing).
     */
    IcebergSink(IcebergConfig config, IcebergWriterFactory writerFactory) {
        this.config = Objects.requireNonNull(config, "config must not be null");
        this.writerFactory = Objects.requireNonNull(writerFactory, "writerFactory must not be null");
    }

    @Override
    public SinkWriter<ProcessedRecord> createWriter(WriterInitContext context) {
        return new IcebergSinkWriter(config, writerFactory.create(config));
    }

    // -------------------------------------------------------------------------
    // SinkWriter implementation
    // -------------------------------------------------------------------------

    /**
     * SinkWriter that handles per-record write logic including retry with
     * exponential backoff.
     */
    static class IcebergSinkWriter implements SinkWriter<ProcessedRecord> {

        private static final Logger LOG = LoggerFactory.getLogger(IcebergSinkWriter.class);

        static final int MAX_RETRIES = 3;
        static final long[] RETRY_DELAYS_MS = {1000L, 2000L, 4000L};

        private final IcebergConfig config;
        private final IcebergTableWriter tableWriter;
        private final TemperatureSummaryAvroMapper avroMapper;

        IcebergSinkWriter(IcebergConfig config, IcebergTableWriter tableWriter) {
            this.config = config;
            this.tableWriter = tableWriter;
            this.avroMapper = new TemperatureSummaryAvroMapper();
            LOG.info("IcebergSinkWriter opened with catalog='{}', warehouse='{}', table='{}'",
                    config.catalogName(), config.warehousePath(), config.tableName());
        }

        @Override
        public void write(ProcessedRecord record, Context context)
                throws IOException, InterruptedException {

            if (ProcessedRecord.STATUS_FAILURE.equals(record.getStatus())) {
                LOG.debug("Skipping FAILURE record for {}/{}",
                        record.getSourceNotification().getBucketUrl(),
                        record.getSourceNotification().getObjectName());
                return;
            }

            List<TemperatureSummary> rows = record.getRecords();
            if (rows.isEmpty()) {
                LOG.debug("Skipping record with no rows for {}/{}",
                        record.getSourceNotification().getBucketUrl(),
                        record.getSourceNotification().getObjectName());
                return;
            }

            writeWithRetry(record);
        }

        @Override
        public void flush(boolean endOfInput) {
            // No buffering — each record is written immediately with retry
        }

        @Override
        public void close() throws Exception {
            if (tableWriter != null) {
                tableWriter.close();
            }
            LOG.info("IcebergSinkWriter closed");
        }

        /**
         * Writes rows to the Iceberg table with exponential backoff retry on failure.
         * Retries up to {@value #MAX_RETRIES} times with delays of 1s, 2s, 4s.
         */
        void writeWithRetry(ProcessedRecord record) throws IOException, InterruptedException {
            Exception lastException = null;
            String sourceRef = record.getSourceNotification().getBucketUrl()
                    + "/" + record.getSourceNotification().getObjectName();

            for (int attempt = 0; attempt < MAX_RETRIES; attempt++) {
                try {
                    List<GenericRecord> avroRecords = avroMapper.toAvroRecords(record.getRecords());
                    tableWriter.write(config.tableName(), avroRecords);
                    LOG.info("Successfully wrote {} rows from {} to Iceberg table '{}'",
                            record.getRecords().size(), sourceRef, config.tableName());
                    return;
                } catch (Exception e) {
                    if (e instanceof NoSuchTableException) {
                        throw new IOException("Iceberg table '" + config.tableName()
                                + "' does not exist. Provision it via Terraform before starting the application.", e);
                    }
                    lastException = e;
                    if (attempt < MAX_RETRIES - 1) {
                        long delay = RETRY_DELAYS_MS[attempt];
                        LOG.warn("Iceberg write failed for {} (attempt {}/{}). Retrying in {}ms.",
                                sourceRef, attempt + 1, MAX_RETRIES, delay, e);
                        sleep(delay);
                    }
                }
            }

            LOG.error("Failed to write to Iceberg table '{}' after {} retries for {}",
                    config.tableName(), MAX_RETRIES, sourceRef, lastException);
            throw new IOException("Iceberg write failed after " + MAX_RETRIES
                    + " retries for " + sourceRef, lastException);
        }

        /** Sleeps for the given duration; extracted for testability. */
        void sleep(long millis) throws InterruptedException {
            Thread.sleep(millis);
        }
    }

    // -------------------------------------------------------------------------
    // Table writer abstraction
    // -------------------------------------------------------------------------

    /**
     * Abstraction for writing rows to an Iceberg table. Allows the actual Iceberg
     * catalog interaction to be swapped out for testing.
     */
    public interface IcebergTableWriter extends AutoCloseable {
        /**
         * Writes a batch of rows to the specified Iceberg table.
         *
         * @param tableName the target Iceberg table name
         * @param rows      list of canonical Avro records
         * @throws Exception on write failure
         */
        void write(String tableName, List<GenericRecord> rows) throws Exception;
    }

    /**
     * Factory for creating {@link IcebergTableWriter} instances.
     */
    @FunctionalInterface
    public interface IcebergWriterFactory extends Serializable {
        IcebergTableWriter create(IcebergConfig config);
    }

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    /**
         * Immutable configuration for the Iceberg catalog connection.
         */
        public record IcebergConfig(
            String warehousePath,
            String catalogName,
            String tableName,
            String catalogImpl,
            String fileIoImpl,
            String jdbcUri,
            String jdbcUser,
            String jdbcPassword) implements Serializable {

            @Serial
            private static final long serialVersionUID = 1L;

            public IcebergConfig(String warehousePath, String catalogName, String tableName) {
                this(warehousePath, catalogName, tableName,
                    GlueCatalog.class.getName(), S3FileIO.class.getName(),
                    null, null, null);
            }

            public static IcebergConfig local(String warehousePath, String catalogName, String tableName) {
                return new IcebergConfig(
                        warehousePath,
                        catalogName,
                        tableName,
                        HadoopCatalog.class.getName(),
                        HadoopFileIO.class.getName(),
                        null,
                        null,
                        null);
                }

                public static IcebergConfig localJdbc(
                    String warehousePath,
                    String catalogName,
                    String tableName,
                    String jdbcUri,
                    String jdbcUser,
                    String jdbcPassword) {
                return new IcebergConfig(
                        warehousePath,
                        catalogName,
                        tableName,
                    JDBC_CATALOG_IMPL,
                    HadoopFileIO.class.getName(),
                    jdbcUri,
                    jdbcUser,
                    jdbcPassword);
            }

            public IcebergConfig {
                Objects.requireNonNull(warehousePath, "warehousePath must not be null");
                Objects.requireNonNull(catalogName, "catalogName must not be null");
                Objects.requireNonNull(tableName, "tableName must not be null");
                Objects.requireNonNull(catalogImpl, "catalogImpl must not be null");
                Objects.requireNonNull(fileIoImpl, "fileIoImpl must not be null");
                if (JDBC_CATALOG_IMPL.equals(catalogImpl)) {
                    Objects.requireNonNull(jdbcUri, "jdbcUri must not be null for JdbcCatalog");
                    Objects.requireNonNull(jdbcUser, "jdbcUser must not be null for JdbcCatalog");
                    Objects.requireNonNull(jdbcPassword, "jdbcPassword must not be null for JdbcCatalog");
                }
            }

            @Override
            public @NotNull String toString() {
                return "IcebergConfig{"
                        + "warehousePath='" + warehousePath + '\''
                        + ", catalogName='" + catalogName + '\''
                        + ", tableName='" + tableName + '\''
                    + ", catalogImpl='" + catalogImpl + '\''
                    + ", fileIoImpl='" + fileIoImpl + '\''
                        + ", jdbcUri='" + jdbcUri + '\''
                        + '}';
            }
        }

    // -------------------------------------------------------------------------
    // Default writer implementation
    // -------------------------------------------------------------------------

    /**
     * Default Iceberg table writer that interacts with an Apache Iceberg catalog.
     *
    * <p>This implementation loads a Glue-backed Iceberg catalog using the configured
    * warehouse path and writes Avro data files through Iceberg's S3 file IO.
     */
    static class DefaultIcebergTableWriter implements IcebergTableWriter {

        private static final Logger LOG = LoggerFactory.getLogger(DefaultIcebergTableWriter.class);

        private final IcebergConfig config;
        private final Catalog catalog;

        DefaultIcebergTableWriter(IcebergConfig config) {
            this.config = config;
            this.catalog = createCatalog(config);
        }

        @Override
        public void write(String tableName, List<GenericRecord> rows) throws Exception {
            if (rows.isEmpty()) {
                return;
            }

            TableIdentifier identifier = parseIdentifier(tableName);
            Table table = loadOrCreateTable(identifier);
            List<GenericRecord> rowsToWrite = dedupeRowsIfLocal(table, rows);

            if (rowsToWrite.isEmpty()) {
                LOG.info("Skipped {} duplicate row(s) for Iceberg table '{}'", rows.size(), tableName);
                return;
            }

            String dataPath = table.location() + "/data/" + UUID.randomUUID() + ".avro";
            OutputFile outputFile = table.io().newOutputFile(dataPath);
            GenericAppenderFactory appenderFactory = new GenericAppenderFactory(table.schema());

            long recordCount = 0L;

            try (FileAppender<org.apache.iceberg.data.Record> appender =
                         appenderFactory.newAppender(outputFile, FileFormat.AVRO)) {
                for (GenericRecord row : rowsToWrite) {
                    appender.add(toIcebergRecord(table.schema(), row));
                    recordCount++;
                }
            }
            // Capture actual file size after the appender is fully closed and flushed to disk
            long fileSize = table.io().newInputFile(dataPath).getLength();

            DataFile dataFile = DataFiles.builder(table.spec())
                    .withPath(outputFile.location())
                    .withFormat(FileFormat.AVRO)
                    .withRecordCount(recordCount)
                    .withFileSizeInBytes(fileSize)
                    .build();

            table.newAppend().appendFile(dataFile).commit();
            LOG.info("Appended {} rows to Iceberg table '{}' via {}",
                    recordCount, tableName, outputFile.location());
        }

        private List<GenericRecord> dedupeRowsIfLocal(Table table, List<GenericRecord> rows) throws IOException {
            if (!JDBC_CATALOG_IMPL.equals(config.catalogImpl())) {
                return rows;
            }

            Set<String> existingRowKeys = new HashSet<>();
            try (CloseableIterable<org.apache.iceberg.data.Record> existingRows = IcebergGenerics.read(table).build()) {
                for (org.apache.iceberg.data.Record existingRow : existingRows) {
                    existingRowKeys.add(rowKey(table.schema(), existingRow));
                }
            }

            List<GenericRecord> filteredRows = new ArrayList<>();
            for (GenericRecord row : rows) {
                String rowKey = rowKey(table.schema(), row);
                if (existingRowKeys.add(rowKey)) {
                    filteredRows.add(row);
                }
            }
            return filteredRows;
        }

        private String rowKey(Schema schema, org.apache.iceberg.data.Record row) {
            StringBuilder keyBuilder = new StringBuilder();
            schema.columns().forEach(field -> keyBuilder
                    .append(field.name())
                    .append('=')
                    .append(String.valueOf(row.getField(field.name())))
                    .append('|'));
            return keyBuilder.toString();
        }

        private String rowKey(Schema schema, GenericRecord row) {
            StringBuilder keyBuilder = new StringBuilder();
            schema.columns().forEach(field -> keyBuilder
                    .append(field.name())
                    .append('=')
                    .append(String.valueOf(row.get(field.name())))
                    .append('|'));
            return keyBuilder.toString();
        }

        @Override
        public void close() throws IOException {
            if (catalog instanceof AutoCloseable closable) {
                try {
                    closable.close();
                } catch (Exception e) {
                    throw new IOException("Failed closing Iceberg catalog", e);
                }
            }
            LOG.info("DefaultIcebergTableWriter closed");
        }

        private Catalog createCatalog(IcebergConfig config) {
            Map<String, String> properties = new HashMap<>();
            properties.put(CatalogProperties.WAREHOUSE_LOCATION, config.warehousePath());
            properties.put(CatalogProperties.FILE_IO_IMPL, config.fileIoImpl());
            if (JDBC_CATALOG_IMPL.equals(config.catalogImpl())) {
                properties.put(CatalogProperties.URI, config.jdbcUri());
                properties.put("jdbc.user", config.jdbcUser());
                properties.put("jdbc.password", config.jdbcPassword());
            }

            return CatalogUtil.loadCatalog(
                    config.catalogImpl(),
                    config.catalogName(),
                    properties,
                    new Configuration());
        }

        private TableIdentifier parseIdentifier(String tableName) {
            if (tableName.contains(".")) {
                return TableIdentifier.parse(tableName);
            }
            return TableIdentifier.of(Namespace.of("default"), tableName);
        }

        private Table loadOrCreateTable(TableIdentifier identifier) {
            try {
                return catalog.loadTable(identifier);
            } catch (NoSuchTableException e) {
                if (!JDBC_CATALOG_IMPL.equals(config.catalogImpl())) {
                    throw e;
                }

                Schema schema = new Schema(
                        Types.NestedField.required(1, "date", Types.StringType.get()),
                        Types.NestedField.required(2, "max_temp", Types.IntegerType.get()),
                        Types.NestedField.required(3, "max_temp_city", Types.StringType.get()),
                        Types.NestedField.required(4, "min_temp", Types.IntegerType.get()),
                        Types.NestedField.required(5, "min_temp_city", Types.StringType.get()));

                if (catalog instanceof SupportsNamespaces namespaceCatalog) {
                    try {
                        namespaceCatalog.createNamespace(identifier.namespace());
                    } catch (AlreadyExistsException ignored) {
                        // Namespace already exists.
                    }
                }

                LOG.info("Creating local Iceberg table '{}' in warehouse '{}'",
                        identifier, config.warehousePath());
                return catalog.createTable(identifier, schema, PartitionSpec.unpartitioned());
            }
        }

        private org.apache.iceberg.data.Record toIcebergRecord(Schema schema, GenericRecord avroRecord) {
            org.apache.iceberg.data.GenericRecord icebergRecord = org.apache.iceberg.data.GenericRecord.create(schema);
            schema.columns().forEach(field -> icebergRecord.setField(field.name(), avroRecord.get(field.name())));
            return icebergRecord;
        }
    }
}
