package org.muralis.datahose.model;

import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.ToString;

import java.io.Serial;
import java.io.Serializable;
import java.util.Objects;

@Getter
@ToString
@EqualsAndHashCode
public class TemperatureSummary implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private final String date;
    private final int maxTemp;
    private final String maxTempCity;
    private final int minTemp;
    private final String minTempCity;

    public TemperatureSummary(String date, int maxTemp, String maxTempCity, int minTemp, String minTempCity) {
        this.date = Objects.requireNonNull(date, "date must not be null");
        this.maxTemp = maxTemp;
        this.maxTempCity = Objects.requireNonNull(maxTempCity, "maxTempCity must not be null");
        this.minTemp = minTemp;
        this.minTempCity = Objects.requireNonNull(minTempCity, "minTempCity must not be null");
    }
}