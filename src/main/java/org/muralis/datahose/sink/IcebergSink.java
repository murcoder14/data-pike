package org.muralis.datahose.sink;

import org.jetbrains.annotations.NotNull;
import org.muralis.datahose.model.ProcessedRecord;
import org.apache.flink.api.connector.sink2.Sink;
import org.apache.flink.api.connector.sink2.SinkWriter;
import org.apache.flink.api.connector.sink2.WriterInitContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.Serial;
import java.io.Serializable;
import java.util.List;
import java.util.Map;
import java.util.Objects;

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

        IcebergSinkWriter(IcebergConfig config, IcebergTableWriter tableWriter) {
            this.config = config;
            this.tableWriter = tableWriter;
            LOG.info("IcebergSinkWriter opened with catalog='{}', warehouse='{}', table='{}'",
                    config.catalogName(), config.warehousePath(), config.tableName());
        }

        @Override
        public void write(ProcessedRecord record, Context context)
                throws IOException, InterruptedException {

            if (ProcessedRecord.STATUS_FAILURE.equals(record.getStatus())) {
                LOG.debug("Skipping FAILURE record for s3://{}/{}",
                        record.getSourceNotification().getBucketUrl(),
                        record.getSourceNotification().getObjectName());
                return;
            }

            List<Map<String, String>> rows = record.getRows();
            if (rows.isEmpty()) {
                LOG.debug("Skipping record with no rows for s3://{}/{}",
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
                    tableWriter.write(config.tableName(), record.getRows());
                    LOG.info("Successfully wrote {} rows from {} to Iceberg table '{}'",
                            record.getRows().size(), sourceRef, config.tableName());
                    return;
                } catch (Exception e) {
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
         * @param rows      list of row maps (column-name → value)
         * @throws Exception on write failure
         */
        void write(String tableName, List<Map<String, String>> rows) throws Exception;
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
        public record IcebergConfig(String warehousePath, String catalogName, String tableName) implements Serializable {

            @Serial
            private static final long serialVersionUID = 1L;

            public IcebergConfig(String warehousePath, String catalogName, String tableName) {
                this.warehousePath = Objects.requireNonNull(warehousePath, "warehousePath must not be null");
                this.catalogName = Objects.requireNonNull(catalogName, "catalogName must not be null");
                this.tableName = Objects.requireNonNull(tableName, "tableName must not be null");
            }

            @Override
            public @NotNull String toString() {
                return "IcebergConfig{"
                        + "warehousePath='" + warehousePath + '\''
                        + ", catalogName='" + catalogName + '\''
                        + ", tableName='" + tableName + '\''
                        + '}';
            }
        }

    // -------------------------------------------------------------------------
    // Default writer implementation
    // -------------------------------------------------------------------------

    /**
     * Default Iceberg table writer that interacts with an Apache Iceberg catalog.
     *
     * <p>In a full deployment this would use the Iceberg API to load a catalog,
     * resolve the table, and append data files. The structure is in place for
     * integration once a running Iceberg catalog (e.g., Glue, Hive, REST) is available.
     */
    static class DefaultIcebergTableWriter implements IcebergTableWriter {

        private static final Logger LOG = LoggerFactory.getLogger(DefaultIcebergTableWriter.class);

        private final IcebergConfig config;

        DefaultIcebergTableWriter(IcebergConfig config) {
            this.config = config;
        }

        @Override
        public void write(String tableName, List<Map<String, String>> rows) throws Exception {
            // TODO: Replace with actual Iceberg catalog interaction:
            //   1. Load catalog using config.warehousePath and config.catalogName
            //   2. Load table by tableName
            //   3. Convert rows (Map<String, String>) to Iceberg GenericRecord using table schema
            //   4. Append records via table.newAppend()
            //
            // Example (pseudo-code):
            //   HadoopCatalog catalog = new HadoopCatalog(conf, config.getWarehousePath());
            //   Table table = catalog.loadTable(TableIdentifier.parse(tableName));
            //   DataWriter<Record> writer = ...;
            //   for (Map<String, String> row : rows) {
            //       GenericRecord record = GenericRecord.create(table.schema());
            //       row.forEach(record::set);
            //       writer.write(record);
            //   }
            //   writer.close();
            //   table.newAppend().appendFile(writer.toDataFile()).commit();

            LOG.info("Writing {} rows to Iceberg table '{}' (catalog='{}', warehouse='{}')",
                    rows.size(), tableName, config.catalogName(), config.warehousePath());
        }

        @Override
        public void close() {
            LOG.info("DefaultIcebergTableWriter closed");
        }
    }
}
