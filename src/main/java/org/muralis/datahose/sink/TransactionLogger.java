package org.muralis.datahose.sink;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.TransactionRecord;
import org.apache.flink.api.connector.sink2.Sink;
import org.apache.flink.api.connector.sink2.SinkWriter;
import org.apache.flink.api.connector.sink2.WriterInitContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.Serializable;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

/**
 * Flink Sink V2 implementation that logs transaction details to the RDS PostgreSQL
 * database via an RDS Proxy JDBC connection.
 *
 * <p>Each incoming {@link ProcessedRecord} is converted to a {@link TransactionRecord}
 * and inserted into the {@code transactions} table. On JDBC connection failures, records
 * are buffered in memory and retried on the next {@link SinkWriter#flush(boolean)} call
 * (triggered by Flink checkpoints).
 */
public class TransactionLogger implements Sink<ProcessedRecord> {

    private static final long serialVersionUID = 1L;

    private final JdbcConfig config;
    private final ConnectionFactory connectionFactory;

    /**
     * Creates a TransactionLogger with the given JDBC configuration.
     *
     * @param config JDBC connection configuration (URL, username, password, Iceberg table name)
     */
    public TransactionLogger(JdbcConfig config) {
        this(config, DefaultConnectionFactory.INSTANCE);
    }

    /**
     * Constructor accepting a custom connection factory (for testing).
     */
    TransactionLogger(JdbcConfig config, ConnectionFactory connectionFactory) {
        this.config = Objects.requireNonNull(config, "config must not be null");
        this.connectionFactory = Objects.requireNonNull(connectionFactory, "connectionFactory must not be null");
    }

    @Override
    public SinkWriter<ProcessedRecord> createWriter(WriterInitContext context) {
        return new TransactionLoggerWriter(config, connectionFactory);
    }

    // -------------------------------------------------------------------------
    // SinkWriter implementation
    // -------------------------------------------------------------------------

    /**
     * SinkWriter that inserts transaction records into PostgreSQL via JDBC.
     * Failed records are buffered and retried on the next flush (checkpoint).
     */
    static class TransactionLoggerWriter implements SinkWriter<ProcessedRecord> {

        private static final Logger LOG = LoggerFactory.getLogger(TransactionLoggerWriter.class);

        static final String INSERT_SQL =
                "INSERT INTO transactions (transaction_id, source_bucket, source_object_key, "
                + "status, start_time, end_time, records_processed, records_written, "
                + "error_message, iceberg_table_name) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        private final JdbcConfig config;
        private final ConnectionFactory connectionFactory;
        private final List<TransactionRecord> buffer;
        private transient Connection connection;

        TransactionLoggerWriter(JdbcConfig config, ConnectionFactory connectionFactory) {
            this.config = config;
            this.connectionFactory = connectionFactory;
            this.buffer = new ArrayList<>();
            LOG.info("TransactionLoggerWriter opened with jdbcUrl='{}'", config.getJdbcUrl());
        }

        @Override
        public void write(ProcessedRecord record, Context context)
                throws IOException, InterruptedException {

            TransactionRecord txRecord = toTransactionRecord(record);
            try {
                insertRecord(txRecord);
            } catch (SQLException e) {
                LOG.warn("Failed to insert transaction record for {}/{}. Buffering for retry on next checkpoint.",
                        txRecord.getSourceBucket(), txRecord.getSourceObjectKey(), e);
                buffer.add(txRecord);
                closeConnection();
            }
        }

        @Override
        public void flush(boolean endOfInput) throws IOException {
            if (buffer.isEmpty()) {
                return;
            }

            LOG.info("Flushing {} buffered transaction records", buffer.size());
            List<TransactionRecord> retryBatch = new ArrayList<>(buffer);
            buffer.clear();

            for (TransactionRecord txRecord : retryBatch) {
                try {
                    insertRecord(txRecord);
                } catch (SQLException e) {
                    LOG.error("Retry failed for transaction record {}/{}. Re-buffering.",
                            txRecord.getSourceBucket(), txRecord.getSourceObjectKey(), e);
                    buffer.add(txRecord);
                    closeConnection();
                }
            }

            if (!buffer.isEmpty()) {
                LOG.warn("{} transaction records remain buffered after flush", buffer.size());
            }
        }

        @Override
        public void close() throws Exception {
            closeConnection();
            if (!buffer.isEmpty()) {
                LOG.warn("Closing with {} unbuffered transaction records", buffer.size());
            }
            LOG.info("TransactionLoggerWriter closed");
        }

        /**
         * Converts a {@link ProcessedRecord} to a {@link TransactionRecord} using the builder.
         */
        TransactionRecord toTransactionRecord(ProcessedRecord record) {
            String sourceBucket = record.getSourceNotification().getBucketUrl();
            String sourceObjectKey = record.getSourceNotification().getObjectName();

            TransactionRecord.Builder builder = TransactionRecord.builder()
                    .transactionId(UUID.randomUUID())
                    .sourceBucket(sourceBucket)
                    .sourceObjectKey(sourceObjectKey)
                    .status(record.getStatus())
                    .startTime(record.getProcessingTime())
                    .endTime(Instant.now())
                    .recordsProcessed(record.getRecordsProcessed())
                    .recordsWritten(record.getRecordsWritten())
                    .icebergTableName(config.getIcebergTableName());

            if (ProcessedRecord.STATUS_FAILURE.equals(record.getStatus())
                    || ProcessedRecord.STATUS_PARTIAL.equals(record.getStatus())) {
                builder.errorMessage(record.getErrorMessage());
            }

            return builder.build();
        }

        /**
         * Inserts a single {@link TransactionRecord} into the database.
         */
        void insertRecord(TransactionRecord txRecord) throws SQLException {
            Connection conn = getOrCreateConnection();
            try (PreparedStatement ps = conn.prepareStatement(INSERT_SQL)) {
                ps.setObject(1, txRecord.getTransactionId());
                ps.setString(2, txRecord.getSourceBucket());
                ps.setString(3, txRecord.getSourceObjectKey());
                ps.setString(4, txRecord.getStatus());
                ps.setTimestamp(5, Timestamp.from(txRecord.getStartTime()));
                ps.setTimestamp(6, txRecord.getEndTime() != null
                        ? Timestamp.from(txRecord.getEndTime()) : null);
                ps.setLong(7, txRecord.getRecordsProcessed());
                ps.setLong(8, txRecord.getRecordsWritten());
                ps.setString(9, txRecord.getErrorMessage());
                ps.setString(10, txRecord.getIcebergTableName());
                ps.executeUpdate();
                LOG.debug("Inserted transaction record {} for {}/{}",
                        txRecord.getTransactionId(),
                        txRecord.getSourceBucket(),
                        txRecord.getSourceObjectKey());
            }
        }

        private Connection getOrCreateConnection() throws SQLException {
            if (connection == null || connection.isClosed()) {
                connection = connectionFactory.create(
                        config.getJdbcUrl(), config.getUsername(), config.getPassword());
            }
            return connection;
        }

        private void closeConnection() {
            if (connection != null) {
                try {
                    connection.close();
                } catch (SQLException e) {
                    LOG.warn("Error closing JDBC connection", e);
                }
                connection = null;
            }
        }

        /** Visible for testing. */
        List<TransactionRecord> getBuffer() {
            return buffer;
        }
    }

    // -------------------------------------------------------------------------
    // Connection factory abstraction
    // -------------------------------------------------------------------------

    /**
     * Factory for creating JDBC connections. Allows the actual connection creation
     * to be swapped out for testing.
     */
    @FunctionalInterface
    public interface ConnectionFactory extends Serializable {
        Connection create(String url, String username, String password) throws SQLException;
    }

    /**
     * Default connection factory using {@link DriverManager}.
     */
    static class DefaultConnectionFactory implements ConnectionFactory {
        private static final long serialVersionUID = 1L;
        static final DefaultConnectionFactory INSTANCE = new DefaultConnectionFactory();

        @Override
        public Connection create(String url, String username, String password) throws SQLException {
            return DriverManager.getConnection(url, username, password);
        }
    }

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    /**
     * Immutable JDBC configuration for the RDS Proxy connection.
     */
    public static class JdbcConfig implements Serializable {

        private static final long serialVersionUID = 1L;

        private final String jdbcUrl;
        private final String username;
        private final String password;
        private final String icebergTableName;

        public JdbcConfig(String jdbcUrl, String username, String password, String icebergTableName) {
            this.jdbcUrl = Objects.requireNonNull(jdbcUrl, "jdbcUrl must not be null");
            this.username = Objects.requireNonNull(username, "username must not be null");
            this.password = Objects.requireNonNull(password, "password must not be null");
            this.icebergTableName = Objects.requireNonNull(icebergTableName, "icebergTableName must not be null");
        }

        public String getJdbcUrl() {
            return jdbcUrl;
        }

        public String getUsername() {
            return username;
        }

        public String getPassword() {
            return password;
        }

        public String getIcebergTableName() {
            return icebergTableName;
        }

        @Override
        public String toString() {
            return "JdbcConfig{"
                    + "jdbcUrl='" + jdbcUrl + '\''
                    + ", username='" + username + '\''
                    + ", icebergTableName='" + icebergTableName + '\''
                    + '}';
        }
    }
}
