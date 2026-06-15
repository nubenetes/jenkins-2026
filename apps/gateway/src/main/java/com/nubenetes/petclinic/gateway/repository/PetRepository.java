package com.nubenetes.petclinic.gateway.repository;

import com.nubenetes.petclinic.gateway.domain.Pet;
import org.springframework.data.domain.Pageable;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Spring Data R2DBC repository for the Pet entity.
 */
@SuppressWarnings("unused")
@Repository
public interface PetRepository extends ReactiveCrudRepository<Pet, Long>, PetRepositoryInternal {
    @Query("SELECT * FROM pet entity WHERE entity.owner_id = :id")
    Flux<Pet> findByOwner(Long id);

    @Query("SELECT * FROM pet entity WHERE entity.owner_id IS NULL")
    Flux<Pet> findAllWhereOwnerIsNull();

    @Override
    <S extends Pet> Mono<S> save(S entity);

    @Override
    Flux<Pet> findAll();

    @Override
    Mono<Pet> findById(Long id);

    @Override
    Mono<Void> deleteById(Long id);
}

interface PetRepositoryInternal {
    <S extends Pet> Mono<S> save(S entity);

    Flux<Pet> findAllBy(Pageable pageable);

    Flux<Pet> findAll();

    Mono<Pet> findById(Long id);
    // this is not supported at the moment because of https://github.com/jhipster/generator-jhipster/issues/18269
    // Flux<Pet> findAllBy(Pageable pageable, Criteria criteria);
}
