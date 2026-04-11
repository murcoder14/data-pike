package org.muralis.datahose.sink;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.sink.IcebergSink.IcebergConfig;
import org.muralis.datahose.sink.IcebergSink.IcebergSinkWriter;
import org.muralis.datahose.sink.IcebergSink.IcebergTableWriter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
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

        writer.write(failureRecord, null);

        assertTrue(tableWriter.writtenBatches.isEmpty(), "FAILURE records should be skipped");
    }

    @Test
    void write_skipsEmptyRows() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        ProcessedRecord emptyRecord = ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(List.of())
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(0)
                .recordsWritten(0)
                .processingTime(Instant.now())
                .build();

        writer.write(emptyRecord, null);

        assertTrue(tableWriter.writtenBatches.isEmpty(), "Empty row records should be skipped");
    }

    @Test
    void write_writesSuccessRecords() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        List<Map<String, String>> rows = List.of(
                Map.of("id", "1", "amount", "100.00"),
                Map.of("id", "2", "amount", "200.00"));

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(rows)
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(2)
                .recordsWritten(2)
                .processingTime(Instant.now())
                .build();

        writer.write(record, null);

        assertEquals(1, tableWriter.writtenBatches.size());
        assertEquals(2, tableWriter.writtenBatches.get(0).size());
    }

    @Test
    void write_writesPartialRecords() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        List<Map<String, String>> rows = List.of(Map.of("id", "1", "amount", "50.00"));

        ProcessedRecord record = ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(rows)
                .status(ProcessedRecord.STATUS_PARTIAL)
                .recordsProcessed(3)
                .recordsWritten(1)
                .errorMessage("2 rows failed parsing")
                .processingTime(Instant.now())
                .build();

        writer.write(record, null);

        assertEquals(1, tableWriter.writtenBatches.size());
        assertEquals(1, tableWriter.writtenBatches.get(0).size());
    }

    @Test
    void writeWithRetry_succeedsOnFirstAttempt() throws Exception {
        RecordingWriter tableWriter = new RecordingWriter();
        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, tableWriter);

        ProcessedRecord record = buildSuccessRecord(List.of(Map.of("id", "1")));
        writer.writeWithRetry(record);

        assertEquals(1, tableWriter.writtenBatches.size());
    }

    @Test
    void writeWithRetry_retriesAndSucceeds() throws Exception {
        AtomicInteger callCount = new AtomicInteger(0);
        IcebergTableWriter failThenSucceed = new IcebergTableWriter() {
            @Override
            public void write(String tableName, List<Map<String, String>> rows) throws Exception {
                if (callCount.incrementAndGet() <= 2) {
                    throw new RuntimeException("Transient error");
                }
            }

            @Override
            public void close() {}
        };

        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, failThenSucceed);
        ProcessedRecord record = buildSuccessRecord(List.of(Map.of("id", "1")));

        writer.writeWithRetry(record);

        assertEquals(3, callCount.get(), "Should have attempted 3 times");
    }

    @Test
    void writeWithRetry_throwsAfterMaxRetries() {
        IcebergTableWriter alwaysFails = new IcebergTableWriter() {
            @Override
            public void write(String tableName, List<Map<String, String>> rows) throws Exception {
                throw new RuntimeException("Persistent failure");
            }

            @Override
            public void close() {}
        };

        NoSleepSinkWriter writer = new NoSleepSinkWriter(CONFIG, alwaysFails);
        ProcessedRecord record = buildSuccessRecord(List.of(Map.of("id", "1")));

        IOException ex = assertThrows(IOException.class, () -> writer.writeWithRetry(record));
        assertTrue(ex.getMessage().contains("Iceberg write failed after 3 retries"));
        assertNotNull(ex.getCause());
        assertEquals("Persistent failure", ex.getCause().getMessage());
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
    void createWriter_returnsWriter() {
        RecordingWriter tableWriter = new RecordingWriter();
        IcebergSink sink = new IcebergSink(CONFIG, cfg -> tableWriter);

        var writer = sink.createWriter(null);
        assertNotNull(writer);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private ProcessedRecord buildSuccessRecord(List<Map<String, String>> rows) {
        return ProcessedRecord.builder()
                .sourceNotification(notification)
                .rows(rows)
                .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(rows.size())
                .recordsWritten(rows.size())
                .processingTime(Instant.now())
                .build();
    }

    /** Recording writer that captures all write calls. */
    private static class RecordingWriter implements IcebergTableWriter {
        final List<List<Map<String, String>>> writtenBatches = new ArrayList<>();

        @Override
        public void write(String tableName, List<Map<String, String>> rows) {
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
