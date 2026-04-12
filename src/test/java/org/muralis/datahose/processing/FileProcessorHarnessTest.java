package org.muralis.datahose.processing;

import org.apache.flink.streaming.api.operators.StreamFlatMap;
import org.apache.flink.streaming.util.OneInputStreamOperatorTestHarness;
import org.junit.jupiter.api.Test;
import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.model.TemperatureSummary;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FileProcessorHarnessTest {

    @Test
    void fileProcessor_emitsTemperatureSummariesForJsonSample() throws Exception {
        FileProcessor processor = new FileProcessor();
        try (OneInputStreamOperatorTestHarness<S3FileContent, ProcessedRecord> harness =
                     new OneInputStreamOperatorTestHarness<>(new StreamFlatMap<>(processor))) {
            harness.open();

            String json = readResource("weather_data.json");
            S3Notification notification = new S3Notification(
                    "s3://test-bucket",
                    "weather_data.json",
                    "2024-01-15T00:00:00Z",
                    "aws:s3");
            byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
            harness.processElement(new S3FileContent(notification, bytes, FileFormat.JSON), 0L);

            List<ProcessedRecord> outputValues = harness.extractOutputValues();
            assertEquals(1, outputValues.size());

            ProcessedRecord record = outputValues.get(0);
            assertEquals(ProcessedRecord.STATUS_SUCCESS, record.getStatus());
            assertEquals(4, record.getRecordsProcessed());

            TemperatureSummary julySecond = record.getRecords().get(1);
            assertEquals("2024-07-02", julySecond.getDate());
            assertEquals(109, julySecond.getMaxTemp());
            assertEquals("Phoenix", julySecond.getMaxTempCity());
            assertEquals(75, julySecond.getMinTemp());
            assertEquals("San Diego", julySecond.getMinTempCity());
            assertTrue(record.getProcessingTime() != null);
        }
    }

    private String readResource(String resourceName) throws Exception {
        try (InputStream inputStream = getClass().getClassLoader().getResourceAsStream(resourceName)) {
            if (inputStream == null) {
                throw new IllegalArgumentException("Missing resource: " + resourceName);
            }
            return new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}