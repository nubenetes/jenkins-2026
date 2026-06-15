package com.nubenetes.petclinic.gateway.repository.rowmapper;

import com.nubenetes.petclinic.gateway.domain.Invoice;
import com.nubenetes.petclinic.gateway.domain.enumeration.InvoiceStatus;
import io.r2dbc.spi.Row;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.function.BiFunction;
import org.springframework.stereotype.Service;

/**
 * Converter between {@link Row} to {@link Invoice}, with proper type conversions.
 */
@Service
public class InvoiceRowMapper implements BiFunction<Row, String, Invoice> {

    private final ColumnConverter converter;

    public InvoiceRowMapper(ColumnConverter converter) {
        this.converter = converter;
    }

    /**
     * Take a {@link Row} and a column prefix, and extract all the fields.
     * @return the {@link Invoice} stored in the database.
     */
    @Override
    public Invoice apply(Row row, String prefix) {
        Invoice entity = new Invoice();
        entity.setId(converter.fromRow(row, prefix + "_id", Long.class));
        entity.setCode(converter.fromRow(row, prefix + "_code", String.class));
        entity.setDate(converter.fromRow(row, prefix + "_date", Instant.class));
        entity.setAmount(converter.fromRow(row, prefix + "_amount", BigDecimal.class));
        entity.setStatus(converter.fromRow(row, prefix + "_status", InvoiceStatus.class));
        return entity;
    }
}
