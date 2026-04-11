package org.muralis.datahose.sink;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.model.TransactionRecord;
import org.muralis.datahose.sink.TransactionLogger.ConnectionFactory;
import org.muralis.datahose.sink.TransactionLogger.JdbcConfig;
import org.muralis.datahose.sink.TransactionLogger.TransactionLoggerWriter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link TransactionLogger} and {@link TransactionLoggerWriter}.
 */
class TransactionLoggerTest {

    private static final JdbcConfig CONFIG = new JdbcConfig(
            "jdbc:postgresql://rds-proxy:5432/pipeline",
            "admin", "secret", "iceberg_table");

    private S3Notification notification;

    @BeforeEach
    void setUp() {
        notification = new S3Notification(
                "s3://input-bucket", "data/file.csv",
                "2024-01-15T10:00:00Z", "aws:s3");
    }

    // -------------------------------------------------------------------------
    // toTransactionRecord conversion tests
    // -------------------------------------------------------------------------

    @Test
    void toTransactionRecord_successRecord() {
        TransactionLoggerWriter writer = createWriter(new NoOpConnectionFactory());

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(List.of(Map.of("id", "1")))
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(10)
                .recordsWritten(10)
                .processingTime(Instant.parse("2024-01-15T10:00:00Z"))
                .build();

        TransactionRecord tx = writer.toTransactionRecord(record);

        assertNotNull(tx.getTransactionId());
        assertEquals("s3://input-bucket", tx.getSourceBucket());
        assertEquals("data/file.csv", tx.getSourceObjectKey());
        assertEquals("SUCCESS", tx.getStatus());
        assertEquals(Instant.parse("2024-01-15T10:00:00Z"), tx.getStartTime());
        assertNotNull(tx.getEndTime());
        assertEquals(10, tx.getRecordsProcessed());
        assertEquals(10, tx.getRecordsWritten());
        assertNull(tx.getErrorMessage());
        assertEquals("iceberg_table", tx.getIcebergTableName());
    }

    @Test
    void toTransactionRecord_failureRecord() {
        TransactionLoggerWriter writer = createWriter(new NoOpConnectionFactory());

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .status(ProcessedRecord.STATUS_FAILURE)
                .recordsProcessed(5)
                .recordsWritten(0)
                .errorMessage("File not found")
                .processingTime(Instant.parse("2024-01-15T10:00:00Z"))
                .build();

        TransactionRecord tx = writer.toTransactionRecord(record);

        assertEquals("FAILURE", tx.getStatus());
        assertEquals(5, tx.getRecordsProcessed());
        assertEquals(0, tx.getRecordsWritten());
        assertEquals("File not found", tx.getErrorMessage());
    }

    @Test
    void toTransactionRecord_partialRecord() {
        TransactionLoggerWriter writer = createWriter(new NoOpConnectionFactory());

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(List.of(Map.of("id", "1")))
                .status(ProcessedRecord.STATUS_PARTIAL)
                .recordsProcessed(10)
                .recordsWritten(7)
                .errorMessage("3 rows failed")
                .processingTime(Instant.parse("2024-01-15T10:00:00Z"))
                .build();

        TransactionRecord tx = writer.toTransactionRecord(record);

        assertEquals("PARTIAL", tx.getStatus());
        assertEquals(10, tx.getRecordsProcessed());
        assertEquals(7, tx.getRecordsWritten());
        assertEquals("3 rows failed", tx.getErrorMessage());
    }

    // -------------------------------------------------------------------------
    // Write and insert tests
    // -------------------------------------------------------------------------

    @Test
    void write_insertsRecordOnSuccess() throws Exception {
        RecordingConnectionFactory factory = new RecordingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        ProcessedRecord record = buildSuccessRecord();
        writer.write(record, null);

        assertEquals(1, factory.insertedCount());
        assertTrue(writer.getBuffer().isEmpty());
    }

    @Test
    void write_buffersRecordOnConnectionFailure() throws Exception {
        FailingConnectionFactory factory = new FailingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        ProcessedRecord record = buildSuccessRecord();
        writer.write(record, null);

        assertEquals(1, writer.getBuffer().size());
        assertEquals("s3://input-bucket", writer.getBuffer().get(0).getSourceBucket());
    }

    @Test
    void write_buffersMultipleRecordsOnFailure() throws Exception {
        FailingConnectionFactory factory = new FailingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        writer.write(buildSuccessRecord(), null);
        writer.write(buildSuccessRecord(), null);

        assertEquals(2, writer.getBuffer().size());
    }

    // -------------------------------------------------------------------------
    // Flush / checkpoint retry tests
    // -------------------------------------------------------------------------

    @Test
    void flush_retriesBufferedRecords() throws Exception {
        FailThenSucceedConnectionFactory factory = new FailThenSucceedConnectionFactory(1);
        TransactionLoggerWriter writer = createWriter(factory);

        // First write fails → buffered
        writer.write(buildSuccessRecord(), null);
        assertEquals(1, writer.getBuffer().size());

        // Flush retries → succeeds
        writer.flush(false);
        assertTrue(writer.getBuffer().isEmpty());
    }

    @Test
    void flush_reBuffersOnPersistentFailure() throws Exception {
        FailingConnectionFactory factory = new FailingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        writer.write(buildSuccessRecord(), null);
        assertEquals(1, writer.getBuffer().size());

        // Flush retries but still fails → re-buffered
        writer.flush(false);
        assertEquals(1, writer.getBuffer().size());
    }

    @Test
    void flush_noOpWhenBufferEmpty() throws IOException {
        RecordingConnectionFactory factory = new RecordingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        writer.flush(false);

        assertEquals(0, factory.insertedCount());
    }

    // -------------------------------------------------------------------------
    // Config and constructor tests
    // -------------------------------------------------------------------------

    @Test
    void jdbcConfig_rejectsNulls() {
        assertThrows(NullPointerException.class, () -> new JdbcConfig(null, "u", "p", "t"));
        assertThrows(NullPointerException.class, () -> new JdbcConfig("url", null, "p", "t"));
        assertThrows(NullPointerException.class, () -> new JdbcConfig("url", "u", null, "t"));
        assertThrows(NullPointerException.class, () -> new JdbcConfig("url", "u", "p", null));
    }

    @Test
    void constructor_rejectsNullConfig() {
        assertThrows(NullPointerException.class, () -> new TransactionLogger(null));
    }

    @Test
    void createWriter_returnsWriter() {
        TransactionLogger sink = new TransactionLogger(CONFIG, new NoOpConnectionFactory());
        var writer = sink.createWriter(null);
        assertNotNull(writer);
    }

    @Test
    void close_closesConnection() throws Exception {
        RecordingConnectionFactory factory = new RecordingConnectionFactory();
        TransactionLoggerWriter writer = createWriter(factory);

        // Trigger connection creation
        writer.write(buildSuccessRecord(), null);
        writer.close();

        assertTrue(factory.lastConnection.closeCalled);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private TransactionLoggerWriter createWriter(ConnectionFactory factory) {
        return new TransactionLoggerWriter(CONFIG, factory);
    }

    private ProcessedRecord buildSuccessRecord() {
        return ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(List.of(Map.of("id", "1")))
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(1)
                .recordsWritten(1)
                .processingTime(Instant.parse("2024-01-15T10:00:00Z"))
                .build();
    }

    // -------------------------------------------------------------------------
    // Test doubles
    // -------------------------------------------------------------------------

    /** Connection factory that does nothing (no-op PreparedStatement). */
    private static class NoOpConnectionFactory implements ConnectionFactory {
        @Override
        public Connection create(String url, String username, String password) throws SQLException {
            return new StubConnection(false);
        }
    }

    /** Connection factory that records inserts via a shared PreparedStatement. */
    private static class RecordingConnectionFactory implements ConnectionFactory {
        StubConnection lastConnection;
        final List<StubPreparedStatement> preparedStatements = new ArrayList<>();

        @Override
        public Connection create(String url, String username, String password) throws SQLException {
            lastConnection = new StubConnection(false) {
                @Override
                public PreparedStatement prepareStatement(String sql) throws SQLException {
                    StubPreparedStatement ps = new StubPreparedStatement();
                    preparedStatements.add(ps);
                    return ps;
                }
            };
            return lastConnection;
        }

        int insertedCount() {
            return preparedStatements.stream()
                    .mapToInt(ps -> ps.executeUpdateCount)
                    .sum();
        }
    }

    /** Connection factory that always throws on getConnection. */
    private static class FailingConnectionFactory implements ConnectionFactory {
        @Override
        public Connection create(String url, String username, String password) throws SQLException {
            throw new SQLException("Connection refused");
        }
    }

    /** Connection factory that fails N times then succeeds. */
    private static class FailThenSucceedConnectionFactory implements ConnectionFactory {
        private int failuresRemaining;

        FailThenSucceedConnectionFactory(int failCount) {
            this.failuresRemaining = failCount;
        }

        @Override
        public Connection create(String url, String username, String password) throws SQLException {
            if (failuresRemaining > 0) {
                failuresRemaining--;
                throw new SQLException("Transient connection error");
            }
            return new StubConnection(false);
        }
    }

    /**
     * Minimal JDBC Connection stub that returns a no-op PreparedStatement.
     * Only implements the methods used by TransactionLoggerWriter.
     */
    private static class StubConnection implements Connection {
        boolean closeCalled = false;
        private boolean closed = false;

        StubConnection(boolean startClosed) {
            this.closed = startClosed;
        }

        @Override
        public PreparedStatement prepareStatement(String sql) throws SQLException {
            return new StubPreparedStatement();
        }

        @Override
        public boolean isClosed() throws SQLException {
            return closed;
        }

        @Override
        public void close() throws SQLException {
            closeCalled = true;
            closed = true;
        }

        // --- Unused Connection methods (minimal stubs) ---
        @Override public java.sql.Statement createStatement() { return null; }
        @Override public java.sql.CallableStatement prepareCall(String sql) { return null; }
        @Override public String nativeSQL(String sql) { return sql; }
        @Override public void setAutoCommit(boolean autoCommit) {}
        @Override public boolean getAutoCommit() { return true; }
        @Override public void commit() {}
        @Override public void rollback() {}
        @Override public java.sql.DatabaseMetaData getMetaData() { return null; }
        @Override public void setReadOnly(boolean readOnly) {}
        @Override public boolean isReadOnly() { return false; }
        @Override public void setCatalog(String catalog) {}
        @Override public String getCatalog() { return null; }
        @Override public void setTransactionIsolation(int level) {}
        @Override public int getTransactionIsolation() { return Connection.TRANSACTION_READ_COMMITTED; }
        @Override public java.sql.SQLWarning getWarnings() { return null; }
        @Override public void clearWarnings() {}
        @Override public java.sql.Statement createStatement(int a, int b) { return null; }
        @Override public PreparedStatement prepareStatement(String sql, int a, int b) { return null; }
        @Override public java.sql.CallableStatement prepareCall(String sql, int a, int b) { return null; }
        @Override public java.util.Map<String, Class<?>> getTypeMap() { return null; }
        @Override public void setTypeMap(java.util.Map<String, Class<?>> map) {}
        @Override public void setHoldability(int holdability) {}
        @Override public int getHoldability() { return 0; }
        @Override public java.sql.Savepoint setSavepoint() { return null; }
        @Override public java.sql.Savepoint setSavepoint(String name) { return null; }
        @Override public void rollback(java.sql.Savepoint savepoint) {}
        @Override public void releaseSavepoint(java.sql.Savepoint savepoint) {}
        @Override public java.sql.Statement createStatement(int a, int b, int c) { return null; }
        @Override public PreparedStatement prepareStatement(String sql, int a, int b, int c) { return null; }
        @Override public java.sql.CallableStatement prepareCall(String sql, int a, int b, int c) { return null; }
        @Override public PreparedStatement prepareStatement(String sql, int autoGeneratedKeys) { return null; }
        @Override public PreparedStatement prepareStatement(String sql, int[] columnIndexes) { return null; }
        @Override public PreparedStatement prepareStatement(String sql, String[] columnNames) { return null; }
        @Override public java.sql.Clob createClob() { return null; }
        @Override public java.sql.Blob createBlob() { return null; }
        @Override public java.sql.NClob createNClob() { return null; }
        @Override public java.sql.SQLXML createSQLXML() { return null; }
        @Override public boolean isValid(int timeout) { return !closed; }
        @Override public void setClientInfo(String name, String value) {}
        @Override public void setClientInfo(java.util.Properties properties) {}
        @Override public String getClientInfo(String name) { return null; }
        @Override public java.util.Properties getClientInfo() { return null; }
        @Override public java.sql.Array createArrayOf(String typeName, Object[] elements) { return null; }
        @Override public java.sql.Struct createStruct(String typeName, Object[] attributes) { return null; }
        @Override public void setSchema(String schema) {}
        @Override public String getSchema() { return null; }
        @Override public void abort(java.util.concurrent.Executor executor) {}
        @Override public void setNetworkTimeout(java.util.concurrent.Executor executor, int milliseconds) {}
        @Override public int getNetworkTimeout() { return 0; }
        @Override public <T> T unwrap(Class<T> iface) { return null; }
        @Override public boolean isWrapperFor(Class<?> iface) { return false; }
    }

    /**
     * Minimal PreparedStatement stub that records executeUpdate calls.
     */
    private static class StubPreparedStatement implements PreparedStatement {
        int executeUpdateCount = 0;

        @Override public int executeUpdate() { executeUpdateCount++; return 1; }
        @Override public void setObject(int parameterIndex, Object x) {}
        @Override public void setString(int parameterIndex, String x) {}
        @Override public void setLong(int parameterIndex, long x) {}
        @Override public void setTimestamp(int parameterIndex, java.sql.Timestamp x) {}
        @Override public void close() {}

        // --- Unused PreparedStatement methods (minimal stubs) ---
        @Override public java.sql.ResultSet executeQuery() { return null; }
        @Override public void setNull(int parameterIndex, int sqlType) {}
        @Override public void setBoolean(int parameterIndex, boolean x) {}
        @Override public void setByte(int parameterIndex, byte x) {}
        @Override public void setShort(int parameterIndex, short x) {}
        @Override public void setInt(int parameterIndex, int x) {}
        @Override public void setFloat(int parameterIndex, float x) {}
        @Override public void setDouble(int parameterIndex, double x) {}
        @Override public void setBigDecimal(int parameterIndex, java.math.BigDecimal x) {}
        @Override public void setBytes(int parameterIndex, byte[] x) {}
        @Override public void setDate(int parameterIndex, java.sql.Date x) {}
        @Override public void setTime(int parameterIndex, java.sql.Time x) {}
        @Override public void setTimestamp(int parameterIndex, java.sql.Timestamp x, java.util.Calendar cal) {}
        @Override public void clearParameters() {}
        @Override public void setObject(int parameterIndex, Object x, int targetSqlType) {}
        @Override public boolean execute() { return false; }
        @Override public void addBatch() {}
        @Override public void setCharacterStream(int parameterIndex, java.io.Reader reader, int length) {}
        @Override public void setRef(int parameterIndex, java.sql.Ref x) {}
        @Override public void setBlob(int parameterIndex, java.sql.Blob x) {}
        @Override public void setClob(int parameterIndex, java.sql.Clob x) {}
        @Override public void setArray(int parameterIndex, java.sql.Array x) {}
        @Override public java.sql.ResultSetMetaData getMetaData() { return null; }
        @Override public void setDate(int parameterIndex, java.sql.Date x, java.util.Calendar cal) {}
        @Override public void setTime(int parameterIndex, java.sql.Time x, java.util.Calendar cal) {}
        @Override public void setNull(int parameterIndex, int sqlType, String typeName) {}
        @Override public void setURL(int parameterIndex, java.net.URL x) {}
        @Override public java.sql.ParameterMetaData getParameterMetaData() { return null; }
        @Override public void setRowId(int parameterIndex, java.sql.RowId x) {}
        @Override public void setNString(int parameterIndex, String value) {}
        @Override public void setNCharacterStream(int parameterIndex, java.io.Reader value, long length) {}
        @Override public void setNClob(int parameterIndex, java.sql.NClob value) {}
        @Override public void setClob(int parameterIndex, java.io.Reader reader, long length) {}
        @Override public void setBlob(int parameterIndex, java.io.InputStream inputStream, long length) {}
        @Override public void setNClob(int parameterIndex, java.io.Reader reader, long length) {}
        @Override public void setSQLXML(int parameterIndex, java.sql.SQLXML xmlObject) {}
        @Override public void setObject(int parameterIndex, Object x, int targetSqlType, int scaleOrLength) {}
        @Override public void setAsciiStream(int parameterIndex, java.io.InputStream x, long length) {}
        @Override public void setBinaryStream(int parameterIndex, java.io.InputStream x, long length) {}
        @Override public void setCharacterStream(int parameterIndex, java.io.Reader reader, long length) {}
        @Override public void setAsciiStream(int parameterIndex, java.io.InputStream x) {}
        @Override public void setBinaryStream(int parameterIndex, java.io.InputStream x) {}
        @Override public void setCharacterStream(int parameterIndex, java.io.Reader reader) {}
        @Override public void setNCharacterStream(int parameterIndex, java.io.Reader value) {}
        @Override public void setClob(int parameterIndex, java.io.Reader reader) {}
        @Override public void setBlob(int parameterIndex, java.io.InputStream inputStream) {}
        @Override public void setNClob(int parameterIndex, java.io.Reader reader) {}
        @Override public java.sql.ResultSet executeQuery(String sql) { return null; }
        @Override public int executeUpdate(String sql) { return 0; }
        @Override public int getMaxFieldSize() { return 0; }
        @Override public void setMaxFieldSize(int max) {}
        @Override public int getMaxRows() { return 0; }
        @Override public void setMaxRows(int max) {}
        @Override public void setEscapeProcessing(boolean enable) {}
        @Override public int getQueryTimeout() { return 0; }
        @Override public void setQueryTimeout(int seconds) {}
        @Override public void cancel() {}
        @Override public java.sql.SQLWarning getWarnings() { return null; }
        @Override public void clearWarnings() {}
        @Override public void setCursorName(String name) {}
        @Override public boolean execute(String sql) { return false; }
        @Override public java.sql.ResultSet getResultSet() { return null; }
        @Override public int getUpdateCount() { return 0; }
        @Override public boolean getMoreResults() { return false; }
        @Override public void setFetchDirection(int direction) {}
        @Override public int getFetchDirection() { return 0; }
        @Override public void setFetchSize(int rows) {}
        @Override public int getFetchSize() { return 0; }
        @Override public int getResultSetConcurrency() { return 0; }
        @Override public int getResultSetType() { return 0; }
        @Override public void addBatch(String sql) {}
        @Override public void clearBatch() {}
        @Override public int[] executeBatch() { return new int[0]; }
        @Override public Connection getConnection() { return null; }
        @Override public boolean getMoreResults(int current) { return false; }
        @Override public java.sql.ResultSet getGeneratedKeys() { return null; }
        @Override public int executeUpdate(String sql, int autoGeneratedKeys) { return 0; }
        @Override public int executeUpdate(String sql, int[] columnIndexes) { return 0; }
        @Override public int executeUpdate(String sql, String[] columnNames) { return 0; }
        @Override public boolean execute(String sql, int autoGeneratedKeys) { return false; }
        @Override public boolean execute(String sql, int[] columnIndexes) { return false; }
        @Override public boolean execute(String sql, String[] columnNames) { return false; }
        @Override public int getResultSetHoldability() { return 0; }
        @Override public boolean isClosed() { return false; }
        @Override public void setPoolable(boolean poolable) {}
        @Override public boolean isPoolable() { return false; }
        @Override public void closeOnCompletion() {}
        @Override public boolean isCloseOnCompletion() { return false; }
        @Override public <T> T unwrap(Class<T> iface) { return null; }
        @Override public boolean isWrapperFor(Class<?> iface) { return false; }
        @Override public void setAsciiStream(int parameterIndex, java.io.InputStream x, int length) {}
        @Override public void setUnicodeStream(int parameterIndex, java.io.InputStream x, int length) {}
        @Override public void setBinaryStream(int parameterIndex, java.io.InputStream x, int length) {}
    }
}
