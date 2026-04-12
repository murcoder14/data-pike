package org.muralis.datahose.processing;

import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.muralis.datahose.model.TemperatureSummary;

import java.util.ArrayList;
import java.util.List;

public final class TemperatureSummaryAvroMapper {

    public List<GenericRecord> toAvroRecords(List<TemperatureSummary> summaries) {
        List<GenericRecord> records = new ArrayList<>();
        for (TemperatureSummary summary : summaries) {
            GenericData.Record record = new GenericData.Record(TemperatureSummarySchemas.TEMPERATURE_SUMMARY);
            record.put("date", summary.getDate());
            record.put("max_temp", summary.getMaxTemp());
            record.put("max_temp_city", summary.getMaxTempCity());
            record.put("min_temp", summary.getMinTemp());
            record.put("min_temp_city", summary.getMinTempCity());
            records.add(record);
        }
        return records;
    }
}