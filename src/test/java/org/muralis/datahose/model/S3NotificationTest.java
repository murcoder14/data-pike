package org.muralis.datahose.model;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class S3NotificationTest {

    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void constructorSetsAllFields() {
        S3Notification n = new S3Notification("s3://bucket", "key.csv", "2024-01-15T00:00:00Z", "aws:s3");
        assertEquals("s3://bucket", n.getBucketUrl());
        assertEquals("key.csv", n.getObjectName());
        assertEquals("2024-01-15T00:00:00Z", n.getEventTime());
        assertEquals("aws:s3", n.getEventSource());
    }

    @Test
    void settersUpdateFields() {
        S3Notification n = new S3Notification();
        n.setBucketUrl("s3://b");
        n.setObjectName("obj");
        n.setEventTime("t");
        n.setEventSource("src");
        assertEquals("s3://b", n.getBucketUrl());
        assertEquals("obj", n.getObjectName());
        assertEquals("t", n.getEventTime());
        assertEquals("src", n.getEventSource());
    }

    @Test
    void equalsAndHashCode() {
        S3Notification a = new S3Notification("s3://b", "o", "t", "s");
        S3Notification b = new S3Notification("s3://b", "o", "t", "s");
        assertEquals(a, b);
        assertEquals(a.hashCode(), b.hashCode());
    }

    @Test
    void notEqualWhenFieldsDiffer() {
        S3Notification a = new S3Notification("s3://b", "o", "t", "s");
        S3Notification b = new S3Notification("s3://other", "o", "t", "s");
        assertNotEquals(a, b);
    }

    @Test
    void toStringContainsFields() {
        S3Notification n = new S3Notification("s3://b", "o", "t", "s");
        String str = n.toString();
        assertTrue(str.contains("s3://b"));
        assertTrue(str.contains("o"));
    }

    @Test
    void jsonRoundTrip() throws Exception {
        S3Notification original = new S3Notification("s3://input", "data/file.csv", "2024-01-15T10:30:00Z", "aws:s3");
        String json = mapper.writeValueAsString(original);
        S3Notification deserialized = mapper.readValue(json, S3Notification.class);
        assertEquals(original, deserialized);
    }

    @Test
    void jsonIgnoresUnknownProperties() throws Exception {
        String json = "{\"bucketUrl\":\"s3://b\",\"objectName\":\"o\",\"eventTime\":\"t\",\"eventSource\":\"s\",\"extra\":\"ignored\"}";
        S3Notification n = mapper.readValue(json, S3Notification.class);
        assertEquals("s3://b", n.getBucketUrl());
    }
}
