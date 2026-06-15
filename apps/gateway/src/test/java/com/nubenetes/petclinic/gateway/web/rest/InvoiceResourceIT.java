package com.nubenetes.petclinic.gateway.web.rest;

import static com.nubenetes.petclinic.gateway.domain.InvoiceAsserts.*;
import static com.nubenetes.petclinic.gateway.web.rest.TestUtil.createUpdateProxyForBean;
import static com.nubenetes.petclinic.gateway.web.rest.TestUtil.sameNumber;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nubenetes.petclinic.gateway.IntegrationTest;
import com.nubenetes.petclinic.gateway.domain.Invoice;
import com.nubenetes.petclinic.gateway.domain.enumeration.InvoiceStatus;
import com.nubenetes.petclinic.gateway.repository.EntityManager;
import com.nubenetes.petclinic.gateway.repository.InvoiceRepository;
import com.nubenetes.petclinic.gateway.service.dto.InvoiceDTO;
import com.nubenetes.petclinic.gateway.service.mapper.InvoiceMapper;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
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
 * Integration tests for the {@link InvoiceResource} REST controller.
 */
@IntegrationTest
@AutoConfigureWebTestClient(timeout = IntegrationTest.DEFAULT_ENTITY_TIMEOUT)
@WithMockUser
class InvoiceResourceIT {

    private static final String DEFAULT_CODE = "AAAAAAAAAA";
    private static final String UPDATED_CODE = "BBBBBBBBBB";

    private static final Instant DEFAULT_DATE = Instant.ofEpochMilli(0L);
    private static final Instant UPDATED_DATE = Instant.now().truncatedTo(ChronoUnit.MILLIS);

    private static final BigDecimal DEFAULT_AMOUNT = new BigDecimal(1);
    private static final BigDecimal UPDATED_AMOUNT = new BigDecimal(2);

    private static final InvoiceStatus DEFAULT_STATUS = InvoiceStatus.PAID;
    private static final InvoiceStatus UPDATED_STATUS = InvoiceStatus.ISSUED;

    private static final String ENTITY_API_URL = "/api/invoices";
    private static final String ENTITY_API_URL_ID = ENTITY_API_URL + "/{id}";

    private static Random random = new Random();
    private static AtomicLong longCount = new AtomicLong(random.nextInt() + (2 * Integer.MAX_VALUE));

    @Autowired
    private ObjectMapper om;

    @Autowired
    private InvoiceRepository invoiceRepository;

    @Autowired
    private InvoiceMapper invoiceMapper;

    @Autowired
    private EntityManager em;

    @Autowired
    private WebTestClient webTestClient;

    private Invoice invoice;

    private Invoice insertedInvoice;

    /**
     * Create an entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Invoice createEntity() {
        return new Invoice().code(DEFAULT_CODE).date(DEFAULT_DATE).amount(DEFAULT_AMOUNT).status(DEFAULT_STATUS);
    }

    /**
     * Create an updated entity for this test.
     *
     * This is a static method, as tests for other entities might also need it,
     * if they test an entity which requires the current entity.
     */
    public static Invoice createUpdatedEntity() {
        return new Invoice().code(UPDATED_CODE).date(UPDATED_DATE).amount(UPDATED_AMOUNT).status(UPDATED_STATUS);
    }

    public static void deleteEntities(EntityManager em) {
        try {
            em.deleteAll(Invoice.class).block();
        } catch (Exception e) {
            // It can fail, if other entities are still referring this - it will be removed later.
        }
    }

    @BeforeEach
    public void initTest() {
        invoice = createEntity();
    }

    @AfterEach
    public void cleanup() {
        if (insertedInvoice != null) {
            invoiceRepository.delete(insertedInvoice).block();
            insertedInvoice = null;
        }
        deleteEntities(em);
    }

    @Test
    void createInvoice() throws Exception {
        long databaseSizeBeforeCreate = getRepositoryCount();
        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);
        var returnedInvoiceDTO = webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isCreated()
            .expectBody(InvoiceDTO.class)
            .returnResult()
            .getResponseBody();

        // Validate the Invoice in the database
        assertIncrementedRepositoryCount(databaseSizeBeforeCreate);
        var returnedInvoice = invoiceMapper.toEntity(returnedInvoiceDTO);
        assertInvoiceUpdatableFieldsEquals(returnedInvoice, getPersistedInvoice(returnedInvoice));

        insertedInvoice = returnedInvoice;
    }

    @Test
    void createInvoiceWithExistingId() throws Exception {
        // Create the Invoice with an existing ID
        invoice.setId(1L);
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        long databaseSizeBeforeCreate = getRepositoryCount();

        // An entity with an existing ID cannot be created, so this API call must fail
        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeCreate);
    }

    @Test
    void checkCodeIsRequired() throws Exception {
        long databaseSizeBeforeTest = getRepositoryCount();
        // set the field null
        invoice.setCode(null);

        // Create the Invoice, which fails.
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        assertSameRepositoryCount(databaseSizeBeforeTest);
    }

    @Test
    void checkDateIsRequired() throws Exception {
        long databaseSizeBeforeTest = getRepositoryCount();
        // set the field null
        invoice.setDate(null);

        // Create the Invoice, which fails.
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        assertSameRepositoryCount(databaseSizeBeforeTest);
    }

    @Test
    void checkAmountIsRequired() throws Exception {
        long databaseSizeBeforeTest = getRepositoryCount();
        // set the field null
        invoice.setAmount(null);

        // Create the Invoice, which fails.
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        assertSameRepositoryCount(databaseSizeBeforeTest);
    }

    @Test
    void checkStatusIsRequired() throws Exception {
        long databaseSizeBeforeTest = getRepositoryCount();
        // set the field null
        invoice.setStatus(null);

        // Create the Invoice, which fails.
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        webTestClient
            .post()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        assertSameRepositoryCount(databaseSizeBeforeTest);
    }

    @Test
    void getAllInvoices() {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        // Get all the invoiceList
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
            .value(hasItem(invoice.getId().intValue()))
            .jsonPath("$.[*].code")
            .value(hasItem(DEFAULT_CODE))
            .jsonPath("$.[*].date")
            .value(hasItem(DEFAULT_DATE.toString()))
            .jsonPath("$.[*].amount")
            .value(hasItem(sameNumber(DEFAULT_AMOUNT)))
            .jsonPath("$.[*].status")
            .value(hasItem(DEFAULT_STATUS.toString()));
    }

    @Test
    void getInvoice() {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        // Get the invoice
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, invoice.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isOk()
            .expectHeader()
            .contentType(MediaType.APPLICATION_JSON)
            .expectBody()
            .jsonPath("$.id")
            .value(is(invoice.getId().intValue()))
            .jsonPath("$.code")
            .value(is(DEFAULT_CODE))
            .jsonPath("$.date")
            .value(is(DEFAULT_DATE.toString()))
            .jsonPath("$.amount")
            .value(is(sameNumber(DEFAULT_AMOUNT)))
            .jsonPath("$.status")
            .value(is(DEFAULT_STATUS.toString()));
    }

    @Test
    void getNonExistingInvoice() {
        // Get the invoice
        webTestClient
            .get()
            .uri(ENTITY_API_URL_ID, Long.MAX_VALUE)
            .accept(MediaType.APPLICATION_PROBLEM_JSON)
            .exchange()
            .expectStatus()
            .isNotFound();
    }

    @Test
    void putExistingInvoice() throws Exception {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the invoice
        Invoice updatedInvoice = invoiceRepository.findById(invoice.getId()).block();
        updatedInvoice.code(UPDATED_CODE).date(UPDATED_DATE).amount(UPDATED_AMOUNT).status(UPDATED_STATUS);
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(updatedInvoice);

        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, invoiceDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertPersistedInvoiceToMatchAllProperties(updatedInvoice);
    }

    @Test
    void putNonExistingInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, invoiceDTO.getId())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithIdMismatchInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void putWithMissingIdPathParamInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .put()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void partialUpdateInvoiceWithPatch() throws Exception {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the invoice using partial update
        Invoice partialUpdatedInvoice = new Invoice();
        partialUpdatedInvoice.setId(invoice.getId());

        partialUpdatedInvoice.code(UPDATED_CODE).amount(UPDATED_AMOUNT);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedInvoice.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedInvoice))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Invoice in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertInvoiceUpdatableFieldsEquals(createUpdateProxyForBean(partialUpdatedInvoice, invoice), getPersistedInvoice(invoice));
    }

    @Test
    void fullUpdateInvoiceWithPatch() throws Exception {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        long databaseSizeBeforeUpdate = getRepositoryCount();

        // Update the invoice using partial update
        Invoice partialUpdatedInvoice = new Invoice();
        partialUpdatedInvoice.setId(invoice.getId());

        partialUpdatedInvoice.code(UPDATED_CODE).date(UPDATED_DATE).amount(UPDATED_AMOUNT).status(UPDATED_STATUS);

        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, partialUpdatedInvoice.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(partialUpdatedInvoice))
            .exchange()
            .expectStatus()
            .isOk();

        // Validate the Invoice in the database

        assertSameRepositoryCount(databaseSizeBeforeUpdate);
        assertInvoiceUpdatableFieldsEquals(partialUpdatedInvoice, getPersistedInvoice(partialUpdatedInvoice));
    }

    @Test
    void patchNonExistingInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If the entity doesn't have an ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, invoiceDTO.getId())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithIdMismatchInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL_ID, longCount.incrementAndGet())
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isBadRequest();

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void patchWithMissingIdPathParamInvoice() throws Exception {
        long databaseSizeBeforeUpdate = getRepositoryCount();
        invoice.setId(longCount.incrementAndGet());

        // Create the Invoice
        InvoiceDTO invoiceDTO = invoiceMapper.toDto(invoice);

        // If url ID doesn't match entity ID, it will throw BadRequestAlertException
        webTestClient
            .patch()
            .uri(ENTITY_API_URL)
            .contentType(MediaType.valueOf("application/merge-patch+json"))
            .bodyValue(om.writeValueAsBytes(invoiceDTO))
            .exchange()
            .expectStatus()
            .isEqualTo(405);

        // Validate the Invoice in the database
        assertSameRepositoryCount(databaseSizeBeforeUpdate);
    }

    @Test
    void deleteInvoice() {
        // Initialize the database
        insertedInvoice = invoiceRepository.save(invoice).block();

        long databaseSizeBeforeDelete = getRepositoryCount();

        // Delete the invoice
        webTestClient
            .delete()
            .uri(ENTITY_API_URL_ID, invoice.getId())
            .accept(MediaType.APPLICATION_JSON)
            .exchange()
            .expectStatus()
            .isNoContent();

        // Validate the database contains one less item
        assertDecrementedRepositoryCount(databaseSizeBeforeDelete);
    }

    protected long getRepositoryCount() {
        return invoiceRepository.count().block();
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

    protected Invoice getPersistedInvoice(Invoice invoice) {
        return invoiceRepository.findById(invoice.getId()).block();
    }

    protected void assertPersistedInvoiceToMatchAllProperties(Invoice expectedInvoice) {
        // Test fails because reactive api returns an empty object instead of null
        // assertInvoiceAllPropertiesEquals(expectedInvoice, getPersistedInvoice(expectedInvoice));
        assertInvoiceUpdatableFieldsEquals(expectedInvoice, getPersistedInvoice(expectedInvoice));
    }

    protected void assertPersistedInvoiceToMatchUpdatableProperties(Invoice expectedInvoice) {
        // Test fails because reactive api returns an empty object instead of null
        // assertInvoiceAllUpdatablePropertiesEquals(expectedInvoice, getPersistedInvoice(expectedInvoice));
        assertInvoiceUpdatableFieldsEquals(expectedInvoice, getPersistedInvoice(expectedInvoice));
    }
}
