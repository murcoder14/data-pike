package org.muralis.datahose.sink;

import org.apache.avro.generic.GenericRecord;
import org.apache.iceberg.hadoop.HadoopCatalog;
import org.apache.iceberg.exceptions.NoSuchTableException;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.model.TemperatureSummary;
import org.muralis.datahose.sink.IcebergSink.IcebergConfig;
import org.muralis.datahose.sink.IcebergSink.IcebergSinkWriter;
import org.muralis.datahose.sink.IcebergSink.IcebergTableWriter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for {@link IcebergSink} and {@link IcebergSinkWriter}.
 */
class IcebergSinkTest {

    private static final IcebergConfig CONFIG = new IcebergConfig(
            "s3://iceberg-warehouse", "my_catalog", "transactions_table");

    private S3Notification notification;

    @BeforeEach
    void setUp() {
        notification = new S3Notification(
                "s3://input-bucket", "data/file.csv",
                "2024-01-15T10:00:00Z", "aws:s3");
    }

    @Test
    void write_skipsFailureRecords() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        ProcessedRecord failureRecord = ProcessedRecord.builder()
                .sourceNotification(notification)
                .status(ProcessedRecord.STATUS_FAILURE)
                .recordsProcessed(0)
                .recordsWritten(0)
                .errorMessage("file not found")
                .processingTime(Instant.now())
                .build();

        try {
            writer.write(failureRecord, null);
        } finally {
            writer.close();
        }

        assertTrue(tableWriter.writtenBatches.isEmpty(), "FAILURE records should be skipped");
    }

    @Test
    void write_skipsEmptyRows() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        ProcessedRecord emptyRecord = ProcessedRecord.builder()
                .sourceNotification(notification)
            .records(List.of())
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(0)
                .recordsWritten(0)
                .processingTime(Instant.now())
                .build();

        try {
            writer.write(emptyRecord, null);
        } finally {
            writer.close();
        }

        assertTrue(tableWriter.writtenBatches.isEmpty(), "Empty row records should be skipped");
    }

    @Test
    void write_writesSuccessRecords() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        List<TemperatureSummary> rows = List.of(
                temperatureSummary(0),
                temperatureSummary(1));

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .records(rows)
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(2)
                .recordsWritten(2)
                .processingTime(Instant.now())
                .build();

        try {
            writer.write(record, null);
        } finally {
            writer.close();
        }

        assertEquals(1, tableWriter.writtenBatches.size());
        assertEquals(2, tableWriter.writtenBatches.get(0).size());
    }

    @Test
    void write_writesPartialRecords() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        List<TemperatureSummary> rows = List.of(temperatureSummary(0));

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .records(rows)
                .status(ProcessedRecord.STATUS_PARTIAL)
                .recordsProcessed(3)
                .recordsWritten(1)
                .errorMessage("2 rows failed parsing")
                .processingTime(Instant.now())
                .build();

        try {
            writer.write(record, null);
        } finally {
            writer.close();
        }

        assertEquals(1, tableWriter.writtenBatches.size());
        assertEquals(1, tableWriter.writtenBatches.get(0).size());
    }

    @Test
    void writeWithRetry_succeedsOnFirstAttempt() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        ProcessedRecord record = buildSuccessRecord(List.of(temperatureSummary(0)));
        try {
            writer.writeWithRetry(record);
        } finally {
            writer.close();
        }

        assertEquals(1, tableWriter.writtenBatches.size());
    }

    @Test
    void writeWithRetry_retriesAndSucceeds() throws Exception {
        AtomicInteger callCount = new AtomicInteger(0);
        IcebergTableWriter failThenSucceed = new IcebergTableWriter() {
            @Override
            public void write(String tableName, List<GenericRecord> rows) throws Exception {
                if (callCount.incrementAndGet() <= 2) {
                    throw new RuntimeException("Transient error");
                }
            }

            @Override
            public void close() {}
        };

        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, failThenSucceed);
        ProcessedRecord record = buildSuccessRecord(List.of(temperatureSummary(0)));

        try {
            writer.writeWithRetry(record);
        } finally {
            writer.close();
        }

        assertEquals(3, callCount.get(), "Should have attempted 3 times");
    }

    @Test
    void writeWithRetry_throwsAfterMaxRetries() {
        IcebergTableWriter alwaysFails = new IcebergTableWriter() {
            @Override
            public void write(String tableName, List<GenericRecord> rows) throws Exception {
                throw new RuntimeException("Persistent failure");
            }

            @Override
            public void close() {}
        };

        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, alwaysFails);
        ProcessedRecord record = buildSuccessRecord(List.of(temperatureSummary(0)));

        IOException ex;
        try {
            ex = assertThrows(IOException.class, () -> writer.writeWithRetry(record));
        } finally {
            try {
                writer.close();
            } catch (Exception exception) {
                fail("Unexpected error closing writer", exception);
            }
        }
        assertTrue(ex.getMessage().contains("Iceberg write failed after 3 retries"));
        assertNotNull(ex.getCause());
        assertEquals("Persistent failure", ex.getCause().getMessage());
    }

    @Test
    void writeWithRetry_failsFastWhenTableMissing() {
        AtomicInteger callCount = new AtomicInteger(0);
        IcebergTableWriter missingTableWriter = new IcebergTableWriter() {
            @Override
            public void write(String tableName, List<GenericRecord> rows) {
                callCount.incrementAndGet();
                throw new NoSuchTableException("missing table");
            }

            @Override
            public void close() {}
        };

        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, missingTableWriter);
        ProcessedRecord record = buildSuccessRecord(List.of(temperatureSummary(0)));

        IOException ex;
        try {
            ex = assertThrows(IOException.class, () -> writer.writeWithRetry(record));
        } finally {
            try {
                writer.close();
            } catch (Exception exception) {
                fail("Unexpected error closing writer", exception);
            }
        }

        assertEquals(1, callCount.get(), "Missing table should not be retried");
        assertTrue(ex.getMessage().contains("Provision it via Terraform"));
        assertTrue(ex.getCause() instanceof NoSuchTableException);
    }

    @Test
    void icebergConfig_rejectsNulls() {
        assertThrows(NullPointerException.class, () -> new IcebergConfig(null, "cat", "tbl"));
        assertThrows(NullPointerException.class, () -> new IcebergConfig("wh", null, "tbl"));
        assertThrows(NullPointerException.class, () -> new IcebergConfig("wh", "cat", null));
    }

    @Test
    void constructor_rejectsNullConfig() {
        assertThrows(NullPointerException.class, () -> new IcebergSink(null));
    }

    @Test
    void localConfig_usesFilesystemCatalog() {
        IcebergConfig localConfig = IcebergConfig.local("file:///tmp/warehouse", "local_catalog", "default.temperature_summary");

        assertEquals(HadoopCatalog.class.getName(), localConfig.catalogImpl());
        assertNull(localConfig.jdbcUri());
        assertNull(localConfig.jdbcUser());
        assertNull(localConfig.jdbcPassword());
    }

    @Test
    void localJdbcConfig_usesJdbcCatalog() {
        IcebergConfig localConfig = IcebergConfig.localJdbc(
                "file:///tmp/warehouse",
                "local_catalog",
                "default.temperature_summary",
                "jdbc:postgresql://localhost:5433/iceberg_catalog",
                "iceberg_user",
                "iceberg_password");

        assertEquals("org.apache.iceberg.jdbc.JdbcCatalog", localConfig.catalogImpl());
        assertEquals("jdbc:postgresql://localhost:5433/iceberg_catalog", localConfig.jdbcUri());
    }

    @Test
    void createWriter_returnsWriter() {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSink sink = new IcebergSink(CONFIG, cfg -> tableWriter);

        var writer = sink.createWriter(null);
        assertNotNull(writer);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private ProcessedRecord buildSuccessRecord(List<TemperatureSummary> rows) {
        return ProcessedRecord.builder()
                .sourceNotification(notification)
                .records(rows)
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(rows.size())
                .recordsWritten(rows.size())
                .processingTime(Instant.now())
                .build();
    }

    private TemperatureSummary temperatureSummary(long recordIndex) {
        return new TemperatureSummary(
                "2024-07-0" + (recordIndex + 1),
                100 + (int) recordIndex,
                "MaxCity" + recordIndex,
                70 + (int) recordIndex,
                "MinCity" + recordIndex);
    }

    /** Recording writer that captures all write calls. */
    private static class RecordingWriter implements IcebergTableWriter {
        final List<List<GenericRecord>> writtenBatches = new ArrayList<>();

        @Override
        public void write(String tableName, List<GenericRecord> rows) {
            writtenBatches.add(new ArrayList<>(rows));
        }

        @Override
        public void close() {}
    }

    /** IcebergSinkWriter subclass that skips sleep during retries for fast tests. */
    private static class NoSleepSinkWriter extends IcebergSinkWriter {
        NoSleepSinkWriter(IcebergConfig config, IcebergTableWriter tableWriter) {
            super(config, tableWriter);
        }

        @Override
        void sleep(long millis) {
            // No-op for tests
        }
    }
}
