package org.muralis.datahose.processing;

import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.io.Serial;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Core transformation logic that processes raw file content into records for the Iceberg sink.
 *
 * <p>Takes {@link S3FileContent} (notification + raw bytes) as input, parses the content
 * as delimited text (CSV), and emits {@link ProcessedRecord} instances carrying the parsed
 * rows plus metadata for both IcebergSink and TransactionLogger.
 *
 * <p>Error handling: catches all processing exceptions, logs errors, and emits a
 * {@link ProcessedRecord} with FAILURE or PARTIAL status so the downstream
 * TransactionLogger can record the outcome.
 */
public class FileProcessor extends RichFlatMapFunction<S3FileContent, ProcessedRecord> {

    @Serial
    private static final long serialVersionUID = 1L;
    private static final Logger LOG = LoggerFactory.getLogger(FileProcessor.class);

    static final String DEFAULT_DELIMITER = ",";

    private final String delimiter;

    /** Creates a FileProcessor using the default comma delimiter. */
    public FileProcessor() {
        this(DEFAULT_DELIMITER);
    }

    /** Creates a FileProcessor with a custom field delimiter. */
    public FileProcessor(String delimiter) {
        this.delimiter = delimiter;
    }

    @Override
    public void flatMap(S3FileContent fileContent, Collector<ProcessedRecord> out) {
        S3Notification notification = fileContent.notification();
        Instant processingTime = Instant.now();

        LOG.info("Processing file: s3://{}/{}",
                notification.getBucketUrl(), notification.getObjectName());

        try {
            List<Map<String, String>> rows = parseContent(fileContent.content());

            if (rows.isEmpty()) {
                LOG.warn("File s3://{}/{} produced zero records",
                        notification.getBucketUrl(), notification.getObjectName());
            }

            out.collect(ProcessedRecord.builder()
                    .sourceNotification(notification)
                    .rows(rows)
                    .status(ProcessedRecord.STATUS_SUCCESS)
                    .recordsProcessed(rows.size())
                    .recordsWritten(rows.size())
                    .processingTime(processingTime)
                    .build());

        } catch (Exception e) {
            LOG.error("Error processing file s3://{}/{}: {}",
                    notification.getBucketUrl(), notification.getObjectName(),
                    e.getMessage(), e);

            out.collect(ProcessedRecord.builder()
                    .sourceNotification(notification)
                    .rows(List.of())
                    .status(ProcessedRecord.STATUS_FAILURE)
                    .recordsProcessed(0)
                    .recordsWritten(0)
                    .errorMessage(e.getMessage())
                    .processingTime(processingTime)
                    .build());
        }
    }

    /**
     * Parses raw byte content as delimited text. The first line is treated as a header
     * row defining column names. Subsequent lines are parsed into maps of
     * column-name → value.
     *
     * <p>Blank lines are skipped. If a data row has fewer fields than the header,
     * missing columns get empty-string values. Extra fields beyond the header are ignored.
     *
     * @param content raw file bytes (UTF-8 encoded)
     * @return list of parsed rows
     */
    List<Map<String, String>> parseContent(byte[] content) throws Exception {
        List<Map<String, String>> rows = new ArrayList<>();

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new ByteArrayInputStream(content), StandardCharsets.UTF_8))) {

            // First non-blank line is the header
            String headerLine = readNextNonBlankLine(reader);
            if (headerLine == null) {
                return rows; // empty file
            }

            String[] headers = headerLine.split(delimiter, -1);
            for (int i = 0; i < headers.length; i++) {
                headers[i] = headers[i].trim();
            }

            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) {
                    continue;
                }

                String[] values = line.split(delimiter, -1);
                Map<String, String> row = new LinkedHashMap<>();
                for (int i = 0; i < headers.length; i++) {
                    row.put(headers[i], i < values.length ? values[i].trim() : "");
                }
                rows.add(row);
            }
        }

        return rows;
    }

    private String readNextNonBlankLine(BufferedReader reader) throws Exception {
        String line;
        while ((line = reader.readLine()) != null) {
            if (!line.isBlank()) {
                return line;
            }
        }
        return null;
    }
}
