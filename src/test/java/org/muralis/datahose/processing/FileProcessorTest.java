package org.muralis.datahose.processing;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.apache.flink.util.Collector;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class FileProcessorTest {

    private FileProcessor processor;
    private TestCollector collector;

    @BeforeEach
    void setUp() {
        processor = new FileProcessor();
        collector = new TestCollector();
    }

    @Test
    void processValidCsvFile() {
        String csv = "name,age,city\nAlice,30,Seattle\nBob,25,Portland\n";
        S3FileContent input = fileContent(csv);

        processor.flatMap(input, collector);

        assertEquals(1, collector.results.size());
        ProcessedRecord record = collector.results.get(0);
        assertEquals(ProcessedRecord.STATUS_SUCCESS, record.getStatus());
        assertEquals(2, record.getRecordsProcessed());
        assertEquals(2, record.getRecordsWritten());
        assertNull(record.getErrorMessage());

        List<Map<String, String>> rows = record.getRows();
        assertEquals("Alice", rows.get(0).get("name"));
        assertEquals("30", rows.get(0).get("age"));
        assertEquals("Seattle", rows.get(0).get("city"));
        assertEquals("Bob", rows.get(1).get("name"));
    }

    @Test
    void processEmptyFile() {
        S3FileContent input = fileContent("");

        processor.flatMap(input, collector);

        assertEquals(1, collector.results.size());
        ProcessedRecord record = collector.results.get(0);
        assertEquals(ProcessedRecord.STATUS_SUCCESS, record.getStatus());
        assertEquals(0, record.getRecordsProcessed());
        assertTrue(record.getRows().isEmpty());
    }

    @Test
    void processHeaderOnlyFile() {
        S3FileContent input = fileContent("col1,col2,col3\n");

        processor.flatMap(input, collector);

        assertEquals(1, collector.results.size());
        ProcessedRecord record = collector.results.get(0);
        assertEquals(ProcessedRecord.STATUS_SUCCESS, record.getStatus());
        assertEquals(0, record.getRecordsProcessed());
    }

    @Test
    void blankLinesAreSkipped() {
        String csv = "id,value\n\n1,hello\n\n2,world\n\n";
        S3FileContent input = fileContent(csv);

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(2, record.getRecordsProcessed());
        assertEquals("1", record.getRows().get(0).get("id"));
        assertEquals("2", record.getRows().get(1).get("id"));
    }

    @Test
    void fewerFieldsThanHeaderGetEmptyValues() {
        String csv = "a,b,c\n1\n";
        S3FileContent input = fileContent(csv);

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        Map<String, String> row = record.getRows().get(0);
        assertEquals("1", row.get("a"));
        assertEquals("", row.get("b"));
        assertEquals("", row.get("c"));
    }

    @Test
    void customDelimiter() {
        FileProcessor tsvProcessor = new FileProcessor("\t");
        String tsv = "name\tage\nAlice\t30\n";
        S3FileContent input = fileContent(tsv);

        tsvProcessor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(1, record.getRecordsProcessed());
        assertEquals("Alice", record.getRows().get(0).get("name"));
        assertEquals("30", record.getRows().get(0).get("age"));
    }

    @Test
    void sourceNotificationIsPreserved() {
        S3FileContent input = fileContent("h\nv\n");

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertNotNull(record.getSourceNotification());
        assertEquals("test-bucket", record.getSourceNotification().getBucketUrl());
        assertEquals("test-key.csv", record.getSourceNotification().getObjectName());
    }

    @Test
    void processingTimeIsSet() {
        S3FileContent input = fileContent("h\nv\n");

        processor.flatMap(input, collector);

        assertNotNull(collector.results.get(0).getProcessingTime());
    }

    // --- helpers ---

    private S3FileContent fileContent(String text) {
        S3Notification notification = new S3Notification(
                "test-bucket", "test-key.csv", "2024-01-15T00:00:00Z", "aws:s3");
        return new S3FileContent(notification, text.getBytes(StandardCharsets.UTF_8));
    }

    /** Simple collector that accumulates results into a list. */
    private static class TestCollector implements Collector<ProcessedRecord> {
        final List<ProcessedRecord> results = new ArrayList<>();

        @Override
        public void collect(ProcessedRecord record) {
            results.add(record);
        }

        @Override
        public void close() {
            // no-op
        }
    }
}
