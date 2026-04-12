package org.muralis.datahose.processing;

import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.S3Notification;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

final class FileFormatDetector {

    private FileFormatDetector() {
    }

    static FileFormat detect(S3Notification notification, byte[] content) {
        String objectName = notification.getObjectName();
        if (objectName != null) {
            String lowerCaseName = objectName.toLowerCase(Locale.ROOT);
            if (lowerCaseName.endsWith(".csv")) {
                return FileFormat.CSV;
            }
            if (lowerCaseName.endsWith(".tsv") || lowerCaseName.endsWith(".tab")) {
                return FileFormat.TSV;
            }
            if (lowerCaseName.endsWith(".json") || lowerCaseName.endsWith(".jsonl") || lowerCaseName.endsWith(".ndjson")) {
                return FileFormat.JSON;
            }
            if (lowerCaseName.endsWith(".xml")) {
                return FileFormat.XML;
            }
        }

        String sample = new String(content, StandardCharsets.UTF_8).stripLeading();
        if (sample.startsWith("{") || sample.startsWith("[")) {
            return FileFormat.JSON;
        }
        if (sample.startsWith("<")) {
            return FileFormat.XML;
        }
        if (sample.contains("\t")) {
            return FileFormat.TSV;
        }
        if (sample.contains(",")) {
            return FileFormat.CSV;
        }
        return FileFormat.UNKNOWN;
    }
}