package org.muralis.datahose.sink;

import org.apache.flink.util.Collector;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.processing.FileProcessor;
import org.muralis.datahose.processing.RabbitMessageFileContentAdapter;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class LocalModeIntegrationTest {

    @TempDir
    Path tempDir;

    @Test
    @Disabled("Uses a local filesystem-backed Iceberg catalog. Enable only for manual validation when you want to exercise file creation end-to-end.")
    void rabbitPayloadToLocalIcebergWritesAvroFile() throws Exception {
        String payload = "{\"date\":\"2026-04-12\",\"city\":\"Bengaluru\",\"temperature\":29}";

        RabbitMessageFileContentAdapter adapter = new RabbitMessageFileContentAdapter("weather-stream");
        ListCollector<S3FileContent> fileContentsCollector = new ListCollector<>();
        adapter.flatMap(payload, fileContentsCollector);

        assertEquals(1, fileContentsCollector.values.size(), "Expected one adapted file-content record");

        FileProcessor processor = new FileProcessor();
        ListCollector<ProcessedRecord> processedCollector = new ListCollector<>();
        processor.flatMap(fileContentsCollector.values.get(0), processedCollector);

        assertEquals(1, processedCollector.values.size(), "Expected one processed record");
        ProcessedRecord processed = processedCollector.values.get(0);
        assertEquals(ProcessedRecord.STATUS_SUCCESS, processed.getStatus());

        Path warehouse = tempDir.resolve("iceberg-warehouse");
        Files.createDirectories(warehouse);

        IcebergSink.IcebergConfig localConfig = IcebergSink.IcebergConfig.local(
                warehouse.toUri().toString(),
                "local_catalog",
                "default.temperature_summary");

        IcebergSink.DefaultIcebergTableWriter tableWriter = new IcebergSink.DefaultIcebergTableWriter(localConfig);
        IcebergSink.IcebergSinkWriter sinkWriter = new IcebergSink.IcebergSinkWriter(localConfig, tableWriter);

        try {
            sinkWriter.write(processed, null);
            sinkWriter.flush(true);
        } finally {
            sinkWriter.close();
        }

        List<Path> avroFiles;
        try (var paths = Files.walk(warehouse)) {
            avroFiles = paths.filter(path -> path.toString().endsWith(".avro")).toList();
        }

        assertFalse(avroFiles.isEmpty(), "Expected Avro files under local Iceberg warehouse");
    }

    private static final class ListCollector<T> implements Collector<T> {
        private final List<T> values = new ArrayList<>();

        @Override
        public void collect(T record) {
            values.add(record);
        }

        @Override
        public void close() {
            // No-op
        }
    }
}
