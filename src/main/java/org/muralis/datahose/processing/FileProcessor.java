package org.muralis.datahose.processing;

import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.ProcessedRecord;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.muralis.datahose.model.TemperatureSummary;
import org.muralis.datahose.model.WeatherObservation;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.Serial;
import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * Core transformation logic that processes raw file content into records for the Iceberg sink.
 *
 * <p>Takes {@link S3FileContent} (notification + raw bytes + detected format) as input,
 * routes the content to a format-specific parser, and emits canonical Avro-backed
 * {@link ProcessedRecord} instances for downstream persistence.
 *
 * <p>Error handling: catches all processing exceptions, logs errors, and emits a
 * {@link ProcessedRecord} with FAILURE or PARTIAL status so the downstream
 * TransactionLogger can record the outcome.
 */
public class FileProcessor extends RichFlatMapFunction<S3FileContent, ProcessedRecord> {

    @Serial
    private static final long serialVersionUID = 1L;
    private static final Logger LOG = LoggerFactory.getLogger(FileProcessor.class);

    private transient Map<FileFormat, StructuredFileParser> parsers;
    private transient TemperatureSummaryCalculator summaryCalculator;

    public FileProcessor() {
        this(defaultParsers(), new TemperatureSummaryCalculator());
    }

            FileProcessor(
                Map<FileFormat, StructuredFileParser> parsers,
            TemperatureSummaryCalculator summaryCalculator) {
        this.parsers = parsers;
            this.summaryCalculator = summaryCalculator;
    }

    @Override
    public void open(OpenContext openContext) {
        initDependenciesIfNeeded();
    }

    @Override
    public void flatMap(S3FileContent fileContent, Collector<ProcessedRecord> out) {
        initDependenciesIfNeeded();

        S3Notification notification = fileContent.notification();
        FileFormat fileFormat = fileContent.format();
        Instant processingTime = Instant.now();

        LOG.info("Processing file: {}/{} as {}",
            notification.getBucketUrl(), notification.getObjectName(), fileFormat);

        try {
            StructuredFileParser parser = requireParser(fileFormat);
            List<WeatherObservation> observations = parser.parse(fileContent.content());
            List<TemperatureSummary> records = summaryCalculator.summarizeByDate(observations);

            if (records.isEmpty()) {
                LOG.warn("File {}/{} produced zero records",
                        notification.getBucketUrl(), notification.getObjectName());
            }

            out.collect(ProcessedRecord.builder()
                    .sourceNotification(notification)
                .fileFormat(fileFormat)
                .records(records)
                    .status(ProcessedRecord.STATUS_SUCCESS)
                .recordsProcessed(records.size())
                .recordsWritten(records.size())
                    .processingTime(processingTime)
                    .build());

        } catch (Exception e) {
                LOG.error("Error processing file {}/{}: {}",
                    notification.getBucketUrl(), notification.getObjectName(),
                    e.getMessage(), e);

            out.collect(ProcessedRecord.builder()
                    .sourceNotification(notification)
                    .fileFormat(fileFormat)
                    .records(List.of())
                    .status(ProcessedRecord.STATUS_FAILURE)
                    .recordsProcessed(0)
                    .recordsWritten(0)
                    .errorMessage(e.getMessage())
                    .processingTime(processingTime)
                    .build());
        }
    }

    private StructuredFileParser requireParser(FileFormat format) {
        StructuredFileParser parser = parsers.get(format);
        if (parser == null) {
            throw new IllegalArgumentException("Unsupported file format: " + format);
        }
        return parser;
    }

    private void initDependenciesIfNeeded() {
        if (parsers == null) {
            parsers = defaultParsers();
        }
        if (summaryCalculator == null) {
            summaryCalculator = new TemperatureSummaryCalculator();
        }
    }

    private static Map<FileFormat, StructuredFileParser> defaultParsers() {
        return Map.of(
                FileFormat.CSV, new DelimitedStructuredFileParser(","),
                FileFormat.TSV, new DelimitedStructuredFileParser("\t"),
                FileFormat.JSON, new JsonStructuredFileParser(),
                FileFormat.XML, new XmlStructuredFileParser());
    }
}
