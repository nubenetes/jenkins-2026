package com.nubenetes.petclinic.gateway.repository;

import com.nubenetes.petclinic.gateway.domain.Payment;
import org.springframework.data.domain.Pageable;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Spring Data R2DBC repository for the Payment entity.
 */
@SuppressWarnings("unused")
@Repository
public interface PaymentRepository extends ReactiveCrudRepository<Payment, Long>, PaymentRepositoryInternal {
    @Query("SELECT * FROM payment entity WHERE entity.invoice_id = :id")
    Flux<Payment> findByInvoice(Long id);

    @Query("SELECT * FROM payment entity WHERE entity.invoice_id IS NULL")
    Flux<Payment> findAllWhereInvoiceIsNull();

    @Override
    <S extends Payment> Mono<S> save(S entity);

    @Override
    Flux<Payment> findAll();

    @Override
    Mono<Payment> findById(Long id);

    @Override
    Mono<Void> deleteById(Long id);
}

interface PaymentRepositoryInternal {
    <S extends Payment> Mono<S> save(S entity);

    Flux<Payment> findAllBy(Pageable pageable);

    Flux<Payment> findAll();

    Mono<Payment> findById(Long id);
    // this is not supported at the moment because of https://github.com/jhipster/generator-jhipster/issues/18269
    // Flux<Payment> findAllBy(Pageable pageable, Criteria criteria);
}
