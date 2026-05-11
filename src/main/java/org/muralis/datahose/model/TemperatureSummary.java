package org.muralis.datahose.model;

import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.ToString;

import java.io.Serial;
import java.io.Serializable;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

@Getter
@ToString
@EqualsAndHashCode
public class TemperatureSummary implements Serializable {

    @Serial
    private static final long serialVersionUID = 2L;

    private final String yyyyMmDd;
    private final Map<String, Double> cityTemps;

    public TemperatureSummary(String yyyyMmDd, Map<String, Double> cityTemps) {
        this.yyyyMmDd = Objects.requireNonNull(yyyyMmDd, "yyyyMmDd must not be null");
        this.cityTemps = new LinkedHashMap<>(
                Objects.requireNonNull(cityTemps, "cityTemps must not be null"));
    }
}