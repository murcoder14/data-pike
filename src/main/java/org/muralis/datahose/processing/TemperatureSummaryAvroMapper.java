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
            record.put("yyyy_mm_dd", summary.getYyyyMmDd());
            record.put("city_temps", summary.getCityTemps());
            records.add(record);
        }
        return records;
    }
}