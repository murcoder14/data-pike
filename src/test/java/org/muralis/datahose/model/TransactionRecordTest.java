package org.muralis.datahose.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class TransactionRecordTest {

    private TransactionRecord.Builder validSuccessBuilder() {
        return TransactionRecord.builder()
                .transactionId(UUID.randomUUID())
                .sourceBucket("input-bucket")
                .sourceObjectKey("data/file.csv")
                .status(TransactionRecord.STATUS_SUCCESS)
                .startTime(Instant.parse("2024-01-15T10:00:00Z"))
                .endTime(Instant.parse("2024-01-15T10:01:00Z"))
                .recordsProcessed(100)
                .recordsWritten(100)
                .icebergTableName("db.table1");
    }

    @Test
    void buildSuccessRecord() {
        TransactionRecord r = validSuccessBuilder().build();
        assertNotNull(r.getTransactionId());
        assertEquals("input-bucket", r.getSourceBucket());
        assertEquals(TransactionRecord.STATUS_SUCCESS, r.getStatus());
        assertNull(r.getErrorMessage());
    }

    @Test
    void buildFailureRecordRequiresErrorMessage() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder().status(TransactionRecord.STATUS_FAILURE).build());
    }

    @Test
    void buildFailureRecordWithErrorMessage() {
        TransactionRecord r = validSuccessBuilder()
                .status(TransactionRecord.STATUS_FAILURE)
                .errorMessage("file not found")
                .build();
        assertEquals("file not found", r.getErrorMessage());
    }

    @Test
    void buildPartialRecordRequiresErrorMessage() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder().status(TransactionRecord.STATUS_PARTIAL).build());
    }

    @Test
    void successStatusRejectsErrorMessage() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder().errorMessage("oops").build());
    }

    @Test
    void recordsWrittenCannotExceedRecordsProcessed() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder().recordsProcessed(10).recordsWritten(11).build());
    }

    @Test
    void endTimeCannotBeBeforeStartTime() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder()
                        .startTime(Instant.parse("2024-01-15T10:00:00Z"))
                        .endTime(Instant.parse("2024-01-15T09:00:00Z"))
                        .build());
    }

    @Test
    void requiredFieldsCannotBeNull() {
        assertThrows(NullPointerException.class, () ->
                TransactionRecord.builder().build());
        assertThrows(NullPointerException.class, () ->
                validSuccessBuilder().transactionId(null).build());
        assertThrows(NullPointerException.class, () ->
                validSuccessBuilder().sourceBucket(null).build());
        assertThrows(NullPointerException.class, () ->
                validSuccessBuilder().sourceObjectKey(null).build());
        assertThrows(NullPointerException.class, () ->
                validSuccessBuilder().status(null).build());
        assertThrows(NullPointerException.class, () ->
                validSuccessBuilder().startTime(null).build());
    }

    @Test
    void invalidStatusRejected() {
        assertThrows(IllegalArgumentException.class, () ->
                validSuccessBuilder().status("UNKNOWN").build());
    }

    @Test
    void endTimeNullIsAllowed() {
        TransactionRecord r = validSuccessBuilder().endTime(null).build();
        assertNull(r.getEndTime());
    }

    @Test
    void equalsAndHashCode() {
        UUID id = UUID.randomUUID();
        Instant start = Instant.now();
        Instant end = start.plusSeconds(60);
        TransactionRecord a = TransactionRecord.builder()
                .transactionId(id).sourceBucket("b").sourceObjectKey("k")
                .status(TransactionRecord.STATUS_SUCCESS)
                .startTime(start).endTime(end)
                .recordsProcessed(10).recordsWritten(10).build();
        TransactionRecord b = TransactionRecord.builder()
                .transactionId(id).sourceBucket("b").sourceObjectKey("k")
                .status(TransactionRecord.STATUS_SUCCESS)
                .startTime(start).endTime(end)
                .recordsProcessed(10).recordsWritten(10).build();
        assertEquals(a, b);
        assertEquals(a.hashCode(), b.hashCode());
    }

    @Test
    void toStringContainsFields() {
        TransactionRecord r = validSuccessBuilder().build();
        String str = r.toString();
        assertTrue(str.contains("input-bucket"));
        assertTrue(str.contains("SUCCESS"));
    }
}
