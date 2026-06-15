package com.nubenetes.petclinic.gateway.service;

import com.nubenetes.petclinic.gateway.repository.OwnerRepository;
import com.nubenetes.petclinic.gateway.service.dto.OwnerDTO;
import com.nubenetes.petclinic.gateway.service.mapper.OwnerMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Service Implementation for managing {@link com.nubenetes.petclinic.gateway.domain.Owner}.
 */
@Service
@Transactional
public class OwnerService {

    private static final Logger LOG = LoggerFactory.getLogger(OwnerService.class);

    private final OwnerRepository ownerRepository;

    private final OwnerMapper ownerMapper;

    public OwnerService(OwnerRepository ownerRepository, OwnerMapper ownerMapper) {
        this.ownerRepository = ownerRepository;
        this.ownerMapper = ownerMapper;
    }

    /**
     * Save a owner.
     *
     * @param ownerDTO the entity to save.
     * @return the persisted entity.
     */
    public Mono<OwnerDTO> save(OwnerDTO ownerDTO) {
        LOG.debug("Request to save Owner : {}", ownerDTO);
        return ownerRepository.save(ownerMapper.toEntity(ownerDTO)).map(ownerMapper::toDto);
    }

    /**
     * Update a owner.
     *
     * @param ownerDTO the entity to save.
     * @return the persisted entity.
     */
    public Mono<OwnerDTO> update(OwnerDTO ownerDTO) {
        LOG.debug("Request to update Owner : {}", ownerDTO);
        return ownerRepository.save(ownerMapper.toEntity(ownerDTO)).map(ownerMapper::toDto);
    }

    /**
     * Partially update a owner.
     *
     * @param ownerDTO the entity to update partially.
     * @return the persisted entity.
     */
    public Mono<OwnerDTO> partialUpdate(OwnerDTO ownerDTO) {
        LOG.debug("Request to partially update Owner : {}", ownerDTO);

        return ownerRepository
            .findById(ownerDTO.getId())
            .map(existingOwner -> {
                ownerMapper.partialUpdate(existingOwner, ownerDTO);

                return existingOwner;
            })
            .flatMap(ownerRepository::save)
            .map(ownerMapper::toDto);
    }

    /**
     * Get all the owners.
     *
     * @return the list of entities.
     */
    @Transactional(readOnly = true)
    public Flux<OwnerDTO> findAll() {
        LOG.debug("Request to get all Owners");
        return ownerRepository.findAll().map(ownerMapper::toDto);
    }

    /**
     * Returns the number of owners available.
     * @return the number of entities in the database.
     *
     */
    public Mono<Long> countAll() {
        return ownerRepository.count();
    }

    /**
     * Get one owner by id.
     *
     * @param id the id of the entity.
     * @return the entity.
     */
    @Transactional(readOnly = true)
    public Mono<OwnerDTO> findOne(Long id) {
        LOG.debug("Request to get Owner : {}", id);
        return ownerRepository.findById(id).map(ownerMapper::toDto);
    }

    /**
     * Delete the owner by id.
     *
     * @param id the id of the entity.
     * @return a Mono to signal the deletion
     */
    public Mono<Void> delete(Long id) {
        LOG.debug("Request to delete Owner : {}", id);
        return ownerRepository.deleteById(id);
    }
}
