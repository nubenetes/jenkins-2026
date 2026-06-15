package com.nubenetes.petclinic.gateway.repository.rowmapper;

import com.nubenetes.petclinic.gateway.domain.Owner;
import io.r2dbc.spi.Row;
import java.util.function.BiFunction;
import org.springframework.stereotype.Service;

/**
 * Converter between {@link Row} to {@link Owner}, with proper type conversions.
 */
@Service
public class OwnerRowMapper implements BiFunction<Row, String, Owner> {

    private final ColumnConverter converter;

    public OwnerRowMapper(ColumnConverter converter) {
        this.converter = converter;
    }

    /**
     * Take a {@link Row} and a column prefix, and extract all the fields.
     * @return the {@link Owner} stored in the database.
     */
    @Override
    public Owner apply(Row row, String prefix) {
        Owner entity = new Owner();
        entity.setId(converter.fromRow(row, prefix + "_id", Long.class));
        entity.setAddress(converter.fromRow(row, prefix + "_address", String.class));
        entity.setCity(converter.fromRow(row, prefix + "_city", String.class));
        entity.setTelephone(converter.fromRow(row, prefix + "_telephone", String.class));
        entity.setCustomerId(converter.fromRow(row, prefix + "_customer_id", Long.class));
        return entity;
    }
}
