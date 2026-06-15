package com.nubenetes.petclinic.gateway.web.rest;

import com.nubenetes.petclinic.gateway.repository.OwnerRepository;
import com.nubenetes.petclinic.gateway.service.OwnerService;
import com.nubenetes.petclinic.gateway.service.dto.OwnerDTO;
import com.nubenetes.petclinic.gateway.web.rest.errors.BadRequestAlertException;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.List;
import java.util.Objects;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import tech.jhipster.web.util.HeaderUtil;
import tech.jhipster.web.util.reactive.ResponseUtil;

/**
 * REST controller for managing {@link com.nubenetes.petclinic.gateway.domain.Owner}.
 */
@RestController
@RequestMapping("/api/owners")
public class OwnerResource {

    private static final Logger LOG = LoggerFactory.getLogger(OwnerResource.class);

    private static final String ENTITY_NAME = "owner";

    @Value("${jhipster.clientApp.name}")
    private String applicationName;

    private final OwnerService ownerService;

    private final OwnerRepository ownerRepository;

    public OwnerResource(OwnerService ownerService, OwnerRepository ownerRepository) {
        this.ownerService = ownerService;
        this.ownerRepository = ownerRepository;
    }

    /**
     * {@code POST  /owners} : Create a new owner.
     *
     * @param ownerDTO the ownerDTO to create.
     * @return the {@link ResponseEntity} with status {@code 201 (Created)} and with body the new ownerDTO, or with status {@code 400 (Bad Request)} if the owner has already an ID.
     * @throws URISyntaxException if the Location URI syntax is incorrect.
     */
    @PostMapping("")
    public Mono<ResponseEntity<OwnerDTO>> createOwner(@RequestBody OwnerDTO ownerDTO) throws URISyntaxException {
        LOG.debug("REST request to save Owner : {}", ownerDTO);
        if (ownerDTO.getId() != null) {
            throw new BadRequestAlertException("A new owner cannot already have an ID", ENTITY_NAME, "idexists");
        }
        return ownerService
            .save(ownerDTO)
            .map(result -> {
                try {
                    return ResponseEntity.created(new URI("/api/owners/" + result.getId()))
                        .headers(HeaderUtil.createEntityCreationAlert(applicationName, true, ENTITY_NAME, result.getId().toString()))
                        .body(result);
                } catch (URISyntaxException e) {
                    throw new RuntimeException(e);
                }
            });
    }

    /**
     * {@code PUT  /owners/:id} : Updates an existing owner.
     *
     * @param id the id of the ownerDTO to save.
     * @param ownerDTO the ownerDTO to update.
     * @return the {@link ResponseEntity} with status {@code 200 (OK)} and with body the updated ownerDTO,
     * or with status {@code 400 (Bad Request)} if the ownerDTO is not valid,
     * or with status {@code 500 (Internal Server Error)} if the ownerDTO couldn't be updated.
     * @throws URISyntaxException if the Location URI syntax is incorrect.
     */
    @PutMapping("/{id}")
    public Mono<ResponseEntity<OwnerDTO>> updateOwner(
        @PathVariable(value = "id", required = false) final Long id,
        @RequestBody OwnerDTO ownerDTO
    ) throws URISyntaxException {
        LOG.debug("REST request to update Owner : {}, {}", id, ownerDTO);
        if (ownerDTO.getId() == null) {
            throw new BadRequestAlertException("Invalid id", ENTITY_NAME, "idnull");
        }
        if (!Objects.equals(id, ownerDTO.getId())) {
            throw new BadRequestAlertException("Invalid ID", ENTITY_NAME, "idinvalid");
        }

        return ownerRepository
            .existsById(id)
            .flatMap(exists -> {
                if (!exists) {
                    return Mono.error(new BadRequestAlertException("Entity not found", ENTITY_NAME, "idnotfound"));
                }

                return ownerService
                    .update(ownerDTO)
                    .switchIfEmpty(Mono.error(new ResponseStatusException(HttpStatus.NOT_FOUND)))
                    .map(result ->
                        ResponseEntity.ok()
                            .headers(HeaderUtil.createEntityUpdateAlert(applicationName, true, ENTITY_NAME, result.getId().toString()))
                            .body(result)
                    );
            });
    }

    /**
     * {@code PATCH  /owners/:id} : Partial updates given fields of an existing owner, field will ignore if it is null
     *
     * @param id the id of the ownerDTO to save.
     * @param ownerDTO the ownerDTO to update.
     * @return the {@link ResponseEntity} with status {@code 200 (OK)} and with body the updated ownerDTO,
     * or with status {@code 400 (Bad Request)} if the ownerDTO is not valid,
     * or with status {@code 404 (Not Found)} if the ownerDTO is not found,
     * or with status {@code 500 (Internal Server Error)} if the ownerDTO couldn't be updated.
     * @throws URISyntaxException if the Location URI syntax is incorrect.
     */
    @PatchMapping(value = "/{id}", consumes = { "application/json", "application/merge-patch+json" })
    public Mono<ResponseEntity<OwnerDTO>> partialUpdateOwner(
        @PathVariable(value = "id", required = false) final Long id,
        @RequestBody OwnerDTO ownerDTO
    ) throws URISyntaxException {
        LOG.debug("REST request to partial update Owner partially : {}, {}", id, ownerDTO);
        if (ownerDTO.getId() == null) {
            throw new BadRequestAlertException("Invalid id", ENTITY_NAME, "idnull");
        }
        if (!Objects.equals(id, ownerDTO.getId())) {
            throw new BadRequestAlertException("Invalid ID", ENTITY_NAME, "idinvalid");
        }

        return ownerRepository
            .existsById(id)
            .flatMap(exists -> {
                if (!exists) {
                    return Mono.error(new BadRequestAlertException("Entity not found", ENTITY_NAME, "idnotfound"));
                }

                Mono<OwnerDTO> result = ownerService.partialUpdate(ownerDTO);

                return result
                    .switchIfEmpty(Mono.error(new ResponseStatusException(HttpStatus.NOT_FOUND)))
                    .map(res ->
                        ResponseEntity.ok()
                            .headers(HeaderUtil.createEntityUpdateAlert(applicationName, true, ENTITY_NAME, res.getId().toString()))
                            .body(res)
                    );
            });
    }

    /**
     * {@code GET  /owners} : get all the owners.
     *
     * @return the {@link ResponseEntity} with status {@code 200 (OK)} and the list of owners in body.
     */
    @GetMapping(value = "", produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<List<OwnerDTO>> getAllOwners() {
        LOG.debug("REST request to get all Owners");
        return ownerService.findAll().collectList();
    }

    /**
     * {@code GET  /owners} : get all the owners as a stream.
     * @return the {@link Flux} of owners.
     */
    @GetMapping(value = "", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<OwnerDTO> getAllOwnersAsStream() {
        LOG.debug("REST request to get all Owners as a stream");
        return ownerService.findAll();
    }

    /**
     * {@code GET  /owners/:id} : get the "id" owner.
     *
     * @param id the id of the ownerDTO to retrieve.
     * @return the {@link ResponseEntity} with status {@code 200 (OK)} and with body the ownerDTO, or with status {@code 404 (Not Found)}.
     */
    @GetMapping("/{id}")
    public Mono<ResponseEntity<OwnerDTO>> getOwner(@PathVariable("id") Long id) {
        LOG.debug("REST request to get Owner : {}", id);
        Mono<OwnerDTO> ownerDTO = ownerService.findOne(id);
        return ResponseUtil.wrapOrNotFound(ownerDTO);
    }

    /**
     * {@code DELETE  /owners/:id} : delete the "id" owner.
     *
     * @param id the id of the ownerDTO to delete.
     * @return the {@link ResponseEntity} with status {@code 204 (NO_CONTENT)}.
     */
    @DeleteMapping("/{id}")
    public Mono<ResponseEntity<Void>> deleteOwner(@PathVariable("id") Long id) {
        LOG.debug("REST request to delete Owner : {}", id);
        return ownerService
            .delete(id)
            .then(
                Mono.just(
                    ResponseEntity.noContent()
                        .headers(HeaderUtil.createEntityDeletionAlert(applicationName, true, ENTITY_NAME, id.toString()))
                        .build()
                )
            );
    }
}
