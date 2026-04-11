-- V1: Create transactions table for Flink pipeline transaction logging
-- Requirements: 7.5

CREATE TABLE transactions (
    transaction_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_bucket     VARCHAR(255) NOT NULL,
    source_object_key VARCHAR(1024) NOT NULL,
    status            VARCHAR(20) NOT NULL CHECK (status IN ('SUCCESS', 'FAILURE', 'PARTIAL')),
    start_time        TIMESTAMPTZ NOT NULL,
    end_time          TIMESTAMPTZ,
    records_processed BIGINT DEFAULT 0,
    records_written   BIGINT DEFAULT 0,
    error_message     TEXT,
    iceberg_table_name VARCHAR(255),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_source ON transactions(source_bucket, source_object_key);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
