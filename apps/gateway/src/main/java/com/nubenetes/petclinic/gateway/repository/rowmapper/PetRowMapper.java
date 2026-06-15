package com.nubenetes.petclinic.gateway.repository.rowmapper;

import com.nubenetes.petclinic.gateway.domain.Pet;
import io.r2dbc.spi.Row;
import java.time.LocalDate;
import java.util.function.BiFunction;
import org.springframework.stereotype.Service;

/**
 * Converter between {@link Row} to {@link Pet}, with proper type conversions.
 */
@Service
public class PetRowMapper implements BiFunction<Row, String, Pet> {

    private final ColumnConverter converter;

    public PetRowMapper(ColumnConverter converter) {
        this.converter = converter;
    }

    /**
     * Take a {@link Row} and a column prefix, and extract all the fields.
     * @return the {@link Pet} stored in the database.
     */
    @Override
    public Pet apply(Row row, String prefix) {
        Pet entity = new Pet();
        entity.setId(converter.fromRow(row, prefix + "_id", Long.class));
        entity.setName(converter.fromRow(row, prefix + "_name", String.class));
        entity.setBirthDate(converter.fromRow(row, prefix + "_birth_date", LocalDate.class));
        entity.setOwnerId(converter.fromRow(row, prefix + "_owner_id", Long.class));
        return entity;
    }
}
