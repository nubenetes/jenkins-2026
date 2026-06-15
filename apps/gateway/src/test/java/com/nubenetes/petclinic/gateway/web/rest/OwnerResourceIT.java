package com.nubenetes.petclinic.gateway.web.rest;

import static com.nubenetes.petclinic.gateway.domain.OwnerAsserts.*;
import static com.nubenetes.petclinic.gateway.web.rest.TestUtil.createUpdateProxyForBean;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nubenetes.petclinic.gateway.IntegrationTest;
import com.nubenetes.petclinic.gateway.domain.Owner;
import com.nubenetes.petclinic.gateway.repository.EntityManager;
import com.nubenetes.petclinic.gateway.repository.OwnerRepository;
import com.nubenetes.petclinic.gateway.service.dto.OwnerDTO;
import com.nubenetes.petclinic.gateway.service.mapper.OwnerMapper;
import java.time.Duration;
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
 * Integration tests for the {@link OwnerResource} REST controller.
 */
@IntegrationTest
@AutoConfigureWebTestClient(timeout = IntegrationTest.DEFAULT_ENTITY_TIMEOUT)
@WithMockUser
class OwnerResourceIT {

    private static final String DEFAULT_ADDRESS = "AAAAAAAAAA";
    private static final String UPDATED_ADDRESS = "BBBBBBBBBB";

    private static final String DEFAULT_CITY = "AAAAAAAAAA";
    private static final String UPDATED_CITY = "BBBBBBBBBB";

    private static final String DEFAULT_TELEPHONE = "AAAAAAAAAA";
    private static final String UPDATED_TELEPHONE = "BBBBBBBBBB";

    private static final String ENTITY_API_URL = "/api/owners";
    private static final String ENTITY_API_URL_ID = ENTITY_API_URL + "/{id}";

    private static Random random = new Random();
    private static AtomicLong longCount = new AtomicLong(random.nextInt() + (2 * Integer.MAX_VALUE));

    @Autowired
    private ObjectMapper om;

    @Autowired
    private OwnerRepository ownerRepository;

    @Autowired
    private OwnerMapper ownerMapper;

    @Autowired
    private EntityManager em;

    @Autowired
    private WebTestClient webTestClient;

    private Owner owner;

    private Owner insertedOwner;

    /**
     * Create an entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Owner createEntity() {
        return new Owner().address(DEFAULT_ADDRESS).city(DEFAULT_CITY).telephone(DEFAULT_TELEPHONE);
    }

    /**
     * Create an updated entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Owner createUpdatedEntity() {
        return new Owner().address(UPDATED_ADDRESS).city(UPDATED_CITY).telephone(UPDATED_TELEPHONE);
    }

    public static void deleteEntities(EntityManager em) {
        try {
            em.deleteAll(Owner.class).block();
        } catch (Exception e) {
            // It can fail, if other entities are still referring this - it will be removed later.
        }
    }

    @BeforeEach
    public void initTest() {
        owner = createEntity();
    }

    @AfterEach
    public void cleanup() {
        if (insertedOwner != null) {
            ownerRepository.delete(insertedOwner).block();
            insertedOwner = null;
        }
        deleteEntities(em);
    }

    @Test
    void createOwner() throws Exception {
        long databaseSizeBeforeCreate = getRepositoryCount();
        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);
        var returnedOwnerDTO = webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isCreated()
            .expectBody(OwnerDTO.class)
            .returnResult()
            .getResponseBody();

        // Validate the Owner in the database
        assertIncrementedRepositoryCount(databaseSizeBeforeCreate);
        var returnedOwner = ownerMapper.toEntity(returnedOwnerDTO);
        assertOwnerUpdatableFieldsEquals(returnedOwner, getPersistedOwner(returnedOwner));

        insertedOwner = returnedOwner;
    }

    @Test
    void createOwnerWithExistingId() throws Exception {
        // Create the Owner with an existing ID
        owner.setId(1L);
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        long databaseSizeBeforeCreate = getRepositoryCount();

        // An entity with an existing ID cannot be created, so this API call must fail
        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeCreate);
    }

    @Test
    void getAllOwnersAsStream() {
        // Initialize the database
        ownerRepository.save(owner).block();

        List<Owner> ownerList = webTestClient
            .get()
            .uri(ENTITY_API_URL)
            .accept(MediaType.APPLICATION_NDJSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentTypeCompatibleWith(MediaType.APPLICATION_NDJSON)
            .returnResult(OwnerDTO.class)
            .getResponseBody()
            .map(ownerMapper::toEntity)
            .filter(owner::equals)
            .collectList()
            .block(Duration.ofSeconds(5));

        assertThat(ownerList).isNotNull();
        assertThat(ownerList).hasSize(1);
        Owner testOwner = ownerList.get(0);

        // Test fails because reactive api returns an empty object instead of null
        // assertOwnerAllPropertiesEquals(owner, testOwner);
        assertOwnerUpdatableFieldsEquals(owner, testOwner);
    }

    @Test
    void getAllOwners() {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        // Get all the ownerList
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
            .value(hasItem(owner.getId().intValue()))
            .jsonPath("$.[*].address")
            .value(hasItem(DEFAULT_ADDRESS))
            .jsonPath("$.[*].city")
            .value(hasItem(DEFAULT_CITY))
            .jsonPath("$.[*].telephone")
            .value(hasItem(DEFAULT_TELEPHONE));
    }

    @Test
    void getOwner() {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        // Get the owner
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, owner.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentType(MediaType.APPLICATION_JSON)
            .expectBody()
            .jsonPath("$.id")
            .value(is(owner.getId().intValue()))
            .jsonPath("$.address")
            .value(is(DEFAULT_ADDRESS))
            .jsonPath("$.city")
            .value(is(DEFAULT_CITY))
            .jsonPath("$.telephone")
            .value(is(DEFAULT_TELEPHONE));
    }

    @Test
    void getNonExistingOwner() {
        // Get the owner
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, Long.MAX_VALUE)
            .accept(MediaType.APPLICATION_PROBLEM_JSON)
            .exchange()
            .expectStatus()
            .isNotFound();
    }

    @Test
    void putExistingOwner() throws Exception {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the owner
        Owner updatedOwner = ownerRepository.findById(owner.getId()).block();
        updatedOwner.address(UPDATED_ADDRESS).city(UPDATED_CITY).telephone(UPDATED_TELEPHONE);
        OwnerDTO ownerDTO = ownerMapper.toDto(updatedOwner);

        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, ownerDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertPersistedOwnerToMatchAllProperties(updatedOwner);
    }

    @Test
    void putNonExistingOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, ownerDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithIdMismatchOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithMissingIdPathParamOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void partialUpdateOwnerWithPatch() throws Exception {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the owner using partial update
        Owner partialUpdatedOwner = new Owner();
        partialUpdatedOwner.setId(owner.getId());

        partialUpdatedOwner.address(UPDATED_ADDRESS).city(UPDATED_CITY).telephone(UPDATED_TELEPHONE);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedOwner.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedOwner))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Owner in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertOwnerUpdatableFieldsEquals(createUpdateProxyForBean(partialUpdatedOwner, owner), getPersistedOwner(owner));
    }

    @Test
    void fullUpdateOwnerWithPatch() throws Exception {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the owner using partial update
        Owner partialUpdatedOwner = new Owner();
        partialUpdatedOwner.setId(owner.getId());

        partialUpdatedOwner.address(UPDATED_ADDRESS).city(UPDATED_CITY).telephone(UPDATED_TELEPHONE);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedOwner.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedOwner))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Owner in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertOwnerUpdatableFieldsEquals(partialUpdatedOwner, getPersistedOwner(partialUpdatedOwner));
    }

    @Test
    void patchNonExistingOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, ownerDTO.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithIdMismatchOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithMissingIdPathParamOwner() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        owner.setId(longCount.incrementAndGet());

        // Create the Owner
        OwnerDTO ownerDTO = ownerMapper.toDto(owner);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(ownerDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Owner in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void deleteOwner() {
        // Initialize the database
        insertedOwner = ownerRepository.save(owner).block();

        long databaseSizeBeforeDelete = getRepositoryCount();

        // Delete the owner
        webTestClient
            .delete()
            .uri(ENTITY_API_URL_ID, owner.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isNoContent();

        // Validate the database contains one less item
        assertDecrementedRepositoryCount(databaseSizeBeforeDelete);
    }

    protected long getRepositoryCount() {
        return ownerRepository.count().block();
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

    protected Owner getPersistedOwner(Owner owner) {
        return ownerRepository.findById(owner.getId()).block();
    }

    protected void assertPersistedOwnerToMatchAllProperties(Owner expectedOwner) {
        // Test fails because reactive api returns an empty object instead of null
        // assertOwnerAllPropertiesEquals(expectedOwner, getPersistedOwner(expectedOwner));
        assertOwnerUpdatableFieldsEquals(expectedOwner, getPersistedOwner(expectedOwner));
    }

    protected void assertPersistedOwnerToMatchUpdatableProperties(Owner expectedOwner) {
        // Test fails because reactive api returns an empty object instead of null
        // assertOwnerAllUpdatablePropertiesEquals(expectedOwner, getPersistedOwner(expectedOwner));
        assertOwnerUpdatableFieldsEquals(expectedOwner, getPersistedOwner(expectedOwner));
    }
}
