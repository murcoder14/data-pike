package org.muralis.datahose.processing;

import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.model.TemperatureSummary;
import org.apache.flink.util.Collector;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

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
        assertEquals(ProcessedRecord.STATUS_FAILURE, record.getStatus());
    }

    @Test
    void processEmptyFile() {
        S3FileContent input = fileContent("");

        processor.flatMap(input, collector);

        assertEquals(1, collector.results.size());
        ProcessedRecord record = collector.results.get(0);
        assertEquals(ProcessedRecord.STATUS_SUCCESS, record.getStatus());
        assertEquals(0, record.getRecordsProcessed());
        assertTrue(record.getRecords().isEmpty());
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
        String csv = "date,city,temperature\n\n2024-07-01,Austin,101\n\n2024-07-01,Dallas,99\n\n";
        S3FileContent input = fileContent(csv);

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(1, record.getRecordsProcessed());
        assertSummary(record.getRecords().get(0), "2024-07-01", 101, "Austin", 99, "Dallas");
    }

    @Test
    void fewerFieldsThanHeaderGetEmptyValues() {
        String csv = "date,city,temperature\n2024-07-01,OnlyCity\n";
        S3FileContent input = fileContent(csv);

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(ProcessedRecord.STATUS_FAILURE, record.getStatus());
    }

    @Test
    void processTsvFile() {
        FileProcessor tsvProcessor = new FileProcessor();
        String tsv = "date\tcity\ttemperature\n2024-07-02\tPhoenix\t109\n2024-07-02\tSan Diego\t75\n";
        S3FileContent input = fileContent("test-key.tsv", tsv);

        tsvProcessor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(1, record.getRecordsProcessed());
        assertEquals(FileFormat.TSV, record.getFileFormat());
        assertSummary(record.getRecords().get(0), "2024-07-02", 109, "Phoenix", 75, "San Diego");
    }

    @Test
    void processJsonSampleFile() throws Exception {
        S3FileContent input = fileContent("weather_data.json", readResource("weather_data.json"));

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(FileFormat.JSON, record.getFileFormat());
        assertEquals(4, record.getRecordsProcessed());
        assertSummary(record.getRecords().get(0), "2024-07-01", 96, "Cincinatti", 78, "Los Angeles");
        assertSummary(record.getRecords().get(3), "2024-07-04", 92, "San Jose", 68, "Nashville");
    }

    @Test
    void processXmlSampleFile() throws Exception {
        S3FileContent input = fileContent("weather_data.xml", readResource("weather_data.xml"));

        processor.flatMap(input, collector);

        ProcessedRecord record = collector.results.get(0);
        assertEquals(FileFormat.XML, record.getFileFormat());
        assertEquals(4, record.getRecordsProcessed());
        assertSummary(record.getRecords().get(0), "2025-07-01", 96, "Dallas-Fort Worth", 78, "Los Angeles");
        assertSummary(record.getRecords().get(3), "2025-07-04", 92, "Nashville", 68, "San Jose");
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
        return fileContent("test-key.csv", text);
    }

    private S3FileContent fileContent(String objectName, String text) {
        S3Notification notification = new S3Notification(
                "test-bucket", objectName, "2024-01-15T00:00:00Z", "aws:s3");
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        return new S3FileContent(notification, bytes, S3FileReader.detectFormat(notification, bytes));
    }

    private String readResource(String resourceName) throws IOException {
        try (InputStream inputStream = getClass().getClassLoader().getResourceAsStream(resourceName)) {
            if (inputStream == null) {
                throw new IllegalArgumentException("Missing resource: " + resourceName);
            }
            return new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private void assertSummary(
            TemperatureSummary record,
            String date,
            int maxTemp,
            String maxTempCity,
            int minTemp,
            String minTempCity) {
        assertEquals(date, record.getDate());
        assertEquals(maxTemp, record.getMaxTemp());
        assertEquals(maxTempCity, record.getMaxTempCity());
        assertEquals(minTemp, record.getMinTemp());
        assertEquals(minTempCity, record.getMinTempCity());
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
