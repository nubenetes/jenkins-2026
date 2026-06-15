package com.nubenetes.petclinic.gateway.web.rest;

import static com.nubenetes.petclinic.gateway.domain.PetAsserts.*;
import static com.nubenetes.petclinic.gateway.web.rest.TestUtil.createUpdateProxyForBean;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nubenetes.petclinic.gateway.IntegrationTest;
import com.nubenetes.petclinic.gateway.domain.Pet;
import com.nubenetes.petclinic.gateway.repository.EntityManager;
import com.nubenetes.petclinic.gateway.repository.PetRepository;
import com.nubenetes.petclinic.gateway.service.dto.PetDTO;
import com.nubenetes.petclinic.gateway.service.mapper.PetMapper;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Random;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.reactive.server.WebTestClient;

/**
 * Integration tests for the {@link PetResource} REST controller.
 */
@IntegrationTest
@AutoConfigureWebTestClient(timeout = IntegrationTest.DEFAULT_ENTITY_TIMEOUT)
@WithMockUser
class PetResourceIT {

    private static final String DEFAULT_NAME = "AAAAAAAAAA";
    private static final String UPDATED_NAME = "BBBBBBBBBB";

    private static final LocalDate DEFAULT_BIRTH_DATE = LocalDate.ofEpochDay(0L);
    private static final LocalDate UPDATED_BIRTH_DATE = LocalDate.now(ZoneId.systemDefault());

    private static final String ENTITY_API_URL = "/api/pets";
    private static final String ENTITY_API_URL_ID = ENTITY_API_URL + "/{id}";

    private static Random random = new Random();
    private static AtomicLong longCount = new AtomicLong(random.nextInt() + (2 * Integer.MAX_VALUE));

    @Autowired
    private ObjectMapper om;

    @Autowired
    private PetRepository petRepository;

    @Autowired
    private PetMapper petMapper;

    @Autowired
    private EntityManager em;

    @Autowired
    private WebTestClient webTestClient;

    private Pet pet;

    private Pet insertedPet;

    /**
     * Create an entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Pet createEntity() {
        return new Pet().name(DEFAULT_NAME).birthDate(DEFAULT_BIRTH_DATE);
    }

    /**
     * Create an updated entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Pet createUpdatedEntity() {
        return new Pet().name(UPDATED_NAME).birthDate(UPDATED_BIRTH_DATE);
    }

    public static void deleteEntities(EntityManager em) {
        try {
            em.deleteAll(Pet.class).block();
        } catch (Exception e) {
            // It can fail, if other entities are still referring this - it will be removed later.
        }
    }

    @BeforeEach
    public void initTest() {
        pet = createEntity();
    }

    @AfterEach
    public void cleanup() {
        if (insertedPet != null) {
            petRepository.delete(insertedPet).block();
            insertedPet = null;
        }
        deleteEntities(em);
    }

    @Test
    void createPet() throws Exception {
        long databaseSizeBeforeCreate = getRepositoryCount();
        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);
        var returnedPetDTO = webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isCreated()
            .expectBody(PetDTO.class)
            .returnResult()
            .getResponseBody();

        // Validate the Pet in the database
        assertIncrementedRepositoryCount(databaseSizeBeforeCreate);
        var returnedPet = petMapper.toEntity(returnedPetDTO);
        assertPetUpdatableFieldsEquals(returnedPet, getPersistedPet(returnedPet));

        insertedPet = returnedPet;
    }

    @Test
    void createPetWithExistingId() throws Exception {
        // Create the Pet with an existing ID
        pet.setId(1L);
        PetDTO petDTO = petMapper.toDto(pet);

        long databaseSizeBeforeCreate = getRepositoryCount();

        // An entity with an existing ID cannot be created, so this API call must fail
        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeCreate);
    }

    @Test
    void checkNameIsRequired() throws Exception {
        long databaseSizeBeforeTest = getRepositoryCount();
        // set the field null
        pet.setName(null);

        // Create the Pet, which fails.
        PetDTO petDTO = petMapper.toDto(pet);

        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        assertSameRepositoryCount(databaseSizeBeforeTest);
    }

    @Test
    void getAllPetsAsStream() {
        // Initialize the database
        petRepository.save(pet).block();

        List<Pet> petList = webTestClient
            .get()
            .uri(ENTITY_API_URL)
            .accept(MediaType.APPLICATION_NDJSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentTypeCompatibleWith(MediaType.APPLICATION_NDJSON)
            .returnResult(PetDTO.class)
            .getResponseBody()
            .map(petMapper::toEntity)
            .filter(pet::equals)
            .collectList()
            .block(Duration.ofSeconds(5));

        assertThat(petList).isNotNull();
        assertThat(petList).hasSize(1);
        Pet testPet = petList.get(0);

        // Test fails because reactive api returns an empty object instead of null
        // assertPetAllPropertiesEquals(pet, testPet);
        assertPetUpdatableFieldsEquals(pet, testPet);
    }

    @Test
    void getAllPets() {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        // Get all the petList
        webTestClient
            .get()
            .uri(ENTITY_API_URL + "?sort=id,desc")
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentType(MediaType.APPLICATION_JSON)
            .expectBody()
            .jsonPath("$.[*].id")
            .value(hasItem(pet.getId().intValue()))
            .jsonPath("$.[*].name")
            .value(hasItem(DEFAULT_NAME))
            .jsonPath("$.[*].birthDate")
            .value(hasItem(DEFAULT_BIRTH_DATE.toString()));
    }

    @Test
    void getPet() {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        // Get the pet
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, pet.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentType(MediaType.APPLICATION_JSON)
            .expectBody()
            .jsonPath("$.id")
            .value(is(pet.getId().intValue()))
            .jsonPath("$.name")
            .value(is(DEFAULT_NAME))
            .jsonPath("$.birthDate")
            .value(is(DEFAULT_BIRTH_DATE.toString()));
    }

    @Test
    void getNonExistingPet() {
        // Get the pet
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, Long.MAX_VALUE)
            .accept(MediaType.APPLICATION_PROBLEM_JSON)
            .exchange()
            .expectStatus()
            .isNotFound();
    }

    @Test
    void putExistingPet() throws Exception {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the pet
        Pet updatedPet = petRepository.findById(pet.getId()).block();
        updatedPet.name(UPDATED_NAME).birthDate(UPDATED_BIRTH_DATE);
        PetDTO petDTO = petMapper.toDto(updatedPet);

        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, petDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertPersistedPetToMatchAllProperties(updatedPet);
    }

    @Test
    void putNonExistingPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, petDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithIdMismatchPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithMissingIdPathParamPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void partialUpdatePetWithPatch() throws Exception {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the pet using partial update
        Pet partialUpdatedPet = new Pet();
        partialUpdatedPet.setId(pet.getId());

        partialUpdatedPet.name(UPDATED_NAME);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedPet.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedPet))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Pet in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertPetUpdatableFieldsEquals(createUpdateProxyForBean(partialUpdatedPet, pet), getPersistedPet(pet));
    }

    @Test
    void fullUpdatePetWithPatch() throws Exception {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the pet using partial update
        Pet partialUpdatedPet = new Pet();
        partialUpdatedPet.setId(pet.getId());

        partialUpdatedPet.name(UPDATED_NAME).birthDate(UPDATED_BIRTH_DATE);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedPet.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedPet))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Pet in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertPetUpdatableFieldsEquals(partialUpdatedPet, getPersistedPet(partialUpdatedPet));
    }

    @Test
    void patchNonExistingPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, petDTO.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithIdMismatchPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithMissingIdPathParamPet() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        pet.setId(longCount.incrementAndGet());

        // Create the Pet
        PetDTO petDTO = petMapper.toDto(pet);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(petDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Pet in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void deletePet() {
        // Initialize the database
        insertedPet = petRepository.save(pet).block();

        long databaseSizeBeforeDelete = getRepositoryCount();

        // Delete the pet
        webTestClient
            .delete()
            .uri(ENTITY_API_URL_ID, pet.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isNoContent();

        // Validate the database contains one less item
        assertDecrementedRepositoryCount(databaseSizeBeforeDelete);
    }

    protected long getRepositoryCount() {
        return petRepository.count().block();
    }

    protected void assertIncrementedRepositoryCount(long countBefore) {
        assertThat(countBefore + 1).isEqualTo(getRepositoryCount());
    }

    protected void assertDecrementedRepositoryCount(long countBefore) {
        assertThat(countBefore - 1).isEqualTo(getRepositoryCount());
    }

    protected void assertSameRepositoryCount(long countBefore) {
        assertThat(countBefore).isEqualTo(getRepositoryCount());
    }

    protected Pet getPersistedPet(Pet pet) {
        return petRepository.findById(pet.getId()).block();
    }

    protected void assertPersistedPetToMatchAllProperties(Pet expectedPet) {
        // Test fails because reactive api returns an empty object instead of null
        // assertPetAllPropertiesEquals(expectedPet, getPersistedPet(expectedPet));
        assertPetUpdatableFieldsEquals(expectedPet, getPersistedPet(expectedPet));
    }

    protected void assertPersistedPetToMatchUpdatableProperties(Pet expectedPet) {
        // Test fails because reactive api returns an empty object instead of null
        // assertPetAllUpdatablePropertiesEquals(expectedPet, getPersistedPet(expectedPet));
        assertPetUpdatableFieldsEquals(expectedPet, getPersistedPet(expectedPet));
    }
}
