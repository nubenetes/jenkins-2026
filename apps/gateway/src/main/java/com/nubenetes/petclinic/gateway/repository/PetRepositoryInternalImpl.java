package com.nubenetes.petclinic.gateway.repository;

import com.nubenetes.petclinic.gateway.domain.Pet;
import com.nubenetes.petclinic.gateway.repository.rowmapper.OwnerRowMapper;
import com.nubenetes.petclinic.gateway.repository.rowmapper.PetRowMapper;
import io.r2dbc.spi.Row;
import io.r2dbc.spi.RowMetadata;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.r2dbc.convert.R2dbcConverter;
import org.springframework.data.r2dbc.core.R2dbcEntityOperations;
import org.springframework.data.r2dbc.core.R2dbcEntityTemplate;
import org.springframework.data.r2dbc.repository.support.SimpleR2dbcRepository;
import org.springframework.data.relational.core.sql.Column;
import org.springframework.data.relational.core.sql.Comparison;
import org.springframework.data.relational.core.sql.Condition;
import org.springframework.data.relational.core.sql.Conditions;
import org.springframework.data.relational.core.sql.Expression;
import org.springframework.data.relational.core.sql.Select;
import org.springframework.data.relational.core.sql.SelectBuilder.SelectFromAndJoinCondition;
import org.springframework.data.relational.core.sql.Table;
import org.springframework.data.relational.repository.support.MappingRelationalEntityInformation;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.r2dbc.core.RowsFetchSpec;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Spring Data R2DBC custom repository implementation for the Pet entity.
 */
@SuppressWarnings("unused")
class PetRepositoryInternalImpl extends SimpleR2dbcRepository<Pet, Long> implements PetRepositoryInternal {

    private final DatabaseClient db;
    private final R2dbcEntityTemplate r2dbcEntityTemplate;
    private final EntityManager entityManager;

    private final OwnerRowMapper ownerMapper;
    private final PetRowMapper petMapper;

    private static final Table entityTable = Table.aliased("pet", EntityManager.ENTITY_ALIAS);
    private static final Table ownerTable = Table.aliased("owner", "owner");

    public PetRepositoryInternalImpl(
        R2dbcEntityTemplate template,
        EntityManager entityManager,
        OwnerRowMapper ownerMapper,
        PetRowMapper petMapper,
        R2dbcEntityOperations entityOperations,
        R2dbcConverter converter
    ) {
        super(
            new MappingRelationalEntityInformation(converter.getMappingContext().getRequiredPersistentEntity(Pet.class)),
            entityOperations,
            converter
        );
        this.db = template.getDatabaseClient();
        this.r2dbcEntityTemplate = template;
        this.entityManager = entityManager;
        this.ownerMapper = ownerMapper;
        this.petMapper = petMapper;
    }

    @Override
    public Flux<Pet> findAllBy(Pageable pageable) {
        return createQuery(pageable, null).all();
    }

    RowsFetchSpec<Pet> createQuery(Pageable pageable, Condition whereClause) {
        List<Expression> columns = PetSqlHelper.getColumns(entityTable, EntityManager.ENTITY_ALIAS);
        columns.addAll(OwnerSqlHelper.getColumns(ownerTable, "owner"));
        SelectFromAndJoinCondition selectFrom = Select.builder()
            .select(columns)
            .from(entityTable)
            .leftOuterJoin(ownerTable)
            .on(Column.create("owner_id", entityTable))
            .equals(Column.create("id", ownerTable));
        // we do not support Criteria here for now as of https://github.com/jhipster/generator-jhipster/issues/18269
        String select = entityManager.createSelect(selectFrom, Pet.class, pageable, whereClause);
        return db.sql(select).map(this::process);
    }

    @Override
    public Flux<Pet> findAll() {
        return findAllBy(null);
    }

    @Override
    public Mono<Pet> findById(Long id) {
        Comparison whereClause = Conditions.isEqual(entityTable.column("id"), Conditions.just(id.toString()));
        return createQuery(null, whereClause).one();
    }

    private Pet process(Row row, RowMetadata metadata) {
        Pet entity = petMapper.apply(row, "e");
        entity.setOwner(ownerMapper.apply(row, "owner"));
        return entity;
    }

    @Override
    public <S extends Pet> Mono<S> save(S entity) {
        return super.save(entity);
    }
}
