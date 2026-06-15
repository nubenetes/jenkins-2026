package com.nubenetes.petclinic.gateway.repository;

import com.nubenetes.petclinic.gateway.domain.Owner;
import org.springframework.data.domain.Pageable;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Spring Data R2DBC repository for the Owner entity.
 */
@SuppressWarnings("unused")
@Repository
public interface OwnerRepository extends ReactiveCrudRepository<Owner, Long>, OwnerRepositoryInternal {
    @Query("SELECT * FROM owner entity WHERE entity.customer_id = :id")
    Flux<Owner> findByCustomer(Long id);

    @Query("SELECT * FROM owner entity WHERE entity.customer_id IS NULL")
    Flux<Owner> findAllWhereCustomerIsNull();

    @Override
    <S extends Owner> Mono<S> save(S entity);

    @Override
    Flux<Owner> findAll();

    @Override
    Mono<Owner> findById(Long id);

    @Override
    Mono<Void> deleteById(Long id);
}

interface OwnerRepositoryInternal {
    <S extends Owner> Mono<S> save(S entity);

    Flux<Owner> findAllBy(Pageable pageable);

    Flux<Owner> findAll();

    Mono<Owner> findById(Long id);
    // this is not supported at the moment because of https://github.com/jhipster/generator-jhipster/issues/18269
    // Flux<Owner> findAllBy(Pageable pageable, Criteria criteria);
}
