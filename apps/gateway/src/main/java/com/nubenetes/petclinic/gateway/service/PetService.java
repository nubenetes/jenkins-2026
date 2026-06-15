package com.nubenetes.petclinic.gateway.service;

import com.nubenetes.petclinic.gateway.repository.PetRepository;
import com.nubenetes.petclinic.gateway.service.dto.PetDTO;
import com.nubenetes.petclinic.gateway.service.mapper.PetMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Service Implementation for managing {@link com.nubenetes.petclinic.gateway.domain.Pet}.
 */
@Service
@Transactional
public class PetService {

    private static final Logger LOG = LoggerFactory.getLogger(PetService.class);

    private final PetRepository petRepository;

    private final PetMapper petMapper;

    public PetService(PetRepository petRepository, PetMapper petMapper) {
        this.petRepository = petRepository;
        this.petMapper = petMapper;
    }

    /**
     * Save a pet.
     *
     * @param petDTO the entity to save.
     * @return the persisted entity.
     */
    public Mono<PetDTO> save(PetDTO petDTO) {
        LOG.debug("Request to save Pet : {}", petDTO);
        return petRepository.save(petMapper.toEntity(petDTO)).map(petMapper::toDto);
    }

    /**
     * Update a pet.
     *
     * @param petDTO the entity to save.
     * @return the persisted entity.
     */
    public Mono<PetDTO> update(PetDTO petDTO) {
        LOG.debug("Request to update Pet : {}", petDTO);
        return petRepository.save(petMapper.toEntity(petDTO)).map(petMapper::toDto);
    }

    /**
     * Partially update a pet.
     *
     * @param petDTO the entity to update partially.
     * @return the persisted entity.
     */
    public Mono<PetDTO> partialUpdate(PetDTO petDTO) {
        LOG.debug("Request to partially update Pet : {}", petDTO);

        return petRepository
            .findById(petDTO.getId())
            .map(existingPet -> {
                petMapper.partialUpdate(existingPet, petDTO);

                return existingPet;
            })
            .flatMap(petRepository::save)
            .map(petMapper::toDto);
    }

    /**
     * Get all the pets.
     *
     * @return the list of entities.
     */
    @Transactional(readOnly = true)
    public Flux<PetDTO> findAll() {
        LOG.debug("Request to get all Pets");
        return petRepository.findAll().map(petMapper::toDto);
    }

    /**
     * Returns the number of pets available.
     * @return the number of entities in the database.
     *
     */
    public Mono<Long> countAll() {
        return petRepository.count();
    }

    /**
     * Get one pet by id.
     *
     * @param id the id of the entity.
     * @return the entity.
     */
    @Transactional(readOnly = true)
    public Mono<PetDTO> findOne(Long id) {
        LOG.debug("Request to get Pet : {}", id);
        return petRepository.findById(id).map(petMapper::toDto);
    }

    /**
     * Delete the pet by id.
     *
     * @param id the id of the entity.
     * @return a Mono to signal the deletion
     */
    public Mono<Void> delete(Long id) {
        LOG.debug("Request to delete Pet : {}", id);
        return petRepository.deleteById(id);
    }
}
