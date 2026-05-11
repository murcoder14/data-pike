package org.muralis.datahose.processing;

import org.muralis.datahose.model.TemperatureSummary;
import org.muralis.datahose.model.WeatherObservation;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class TemperatureSummaryCalculator {

    List<TemperatureSummary> summarizeByDate(List<WeatherObservation> observations) {
        Map<String, DailyAccumulator> summariesByDate = new LinkedHashMap<>();
        for (WeatherObservation observation : observations) {
            summariesByDate.computeIfAbsent(observation.getDate(), ignored -> new DailyAccumulator())
                    .accept(observation);
        }

        List<Map.Entry<String, DailyAccumulator>> entries = new ArrayList<>(summariesByDate.entrySet());
        entries.sort(Map.Entry.comparingByKey(Comparator.naturalOrder()));

        List<TemperatureSummary> summaries = new ArrayList<>();
        for (Map.Entry<String, DailyAccumulator> entry : entries) {
            DailyAccumulator accumulator = entry.getValue();
            Map<String, Double> cityTemps = new LinkedHashMap<>();
            cityTemps.put(accumulator.maxTempCity, (double) accumulator.maxTemp);
            if (!accumulator.maxTempCity.equals(accumulator.minTempCity)) {
                cityTemps.put(accumulator.minTempCity, (double) accumulator.minTemp);
            }
            summaries.add(new TemperatureSummary(entry.getKey(), cityTemps));
        }
        return summaries;
    }

    private static final class DailyAccumulator {
        private int maxTemp = Integer.MIN_VALUE;
        private String maxTempCity = "";
        private int minTemp = Integer.MAX_VALUE;
        private String minTempCity = "";

        private void accept(WeatherObservation observation) {
            if (observation.getTemperature() > maxTemp) {
                maxTemp = observation.getTemperature();
                maxTempCity = observation.getCity();
            }
            if (observation.getTemperature() < minTemp) {
                minTemp = observation.getTemperature();
                minTempCity = observation.getCity();
            }
        }
    }
}