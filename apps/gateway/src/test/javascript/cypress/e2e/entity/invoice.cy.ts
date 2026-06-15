import {
  entityConfirmDeleteButtonSelector,
  entityCreateButtonSelector,
  entityCreateCancelButtonSelector,
  entityCreateSaveButtonSelector,
  entityDeleteButtonSelector,
  entityDetailsBackButtonSelector,
  entityDetailsButtonSelector,
  entityEditButtonSelector,
  entityTableSelector,
} from '../../support/entity';

describe('Invoice e2e test', () => {
  const invoicePageUrl = '/invoice';
  const invoicePageUrlPattern = new RegExp('/invoice(\\?.*)?$');
  const username = Cypress.env('E2E_USERNAME') ?? 'user';
  const password = Cypress.env('E2E_PASSWORD') ?? 'user';
  const invoiceSample = { code: 'pish amid pale', date: '2026-06-14T20:35:58.213Z', amount: 19238.81, status: 'ISSUED' };

  let invoice;

  beforeEach(() => {
    cy.login(username, password);
  });

  beforeEach(() => {
    cy.intercept('GET', '/api/invoices+(?*|)').as('entitiesRequest');
    cy.intercept('POST', '/api/invoices').as('postEntityRequest');
    cy.intercept('DELETE', '/api/invoices/*').as('deleteEntityRequest');
  });

  afterEach(() => {
    if (invoice) {
      cy.authenticatedRequest({
        method: 'DELETE',
        url: `/api/invoices/${invoice.id}`,
      }).then(() => {
        invoice = undefined;
      });
    }
  });

  it('Invoices menu should load Invoices page', () => {
    cy.visit('/');
    cy.clickOnEntityMenuItem('invoice');
    cy.wait('@entitiesRequest').then(({ response }) => {
      if (response?.body.length === 0) {
        cy.get(entityTableSelector).should('not.exist');
      } else {
        cy.get(entityTableSelector).should('exist');
      }
    });
    cy.getEntityHeading('Invoice').should('exist');
    cy.url().should('match', invoicePageUrlPattern);
  });

  describe('Invoice page', () => {
    describe('create button click', () => {
      beforeEach(() => {
        cy.visit(invoicePageUrl);
        cy.wait('@entitiesRequest');
      });

      it('should load create Invoice page', () => {
        cy.get(entityCreateButtonSelector).click();
        cy.url().should('match', new RegExp('/invoice/new$'));
        cy.getEntityCreateUpdateHeading('Invoice');
        cy.get(entityCreateSaveButtonSelector).should('exist');
        cy.get(entityCreateCancelButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', invoicePageUrlPattern);
      });
    });

    describe('with existing value', () => {
      beforeEach(() => {
        cy.authenticatedRequest({
          method: 'POST',
          url: '/api/invoices',
          body: invoiceSample,
        }).then(({ body }) => {
          invoice = body;

          cy.intercept(
            {
              method: 'GET',
              url: '/api/invoices+(?*|)',
              times: 1,
            },
            {
              statusCode: 200,
              headers: {
                link: '<http://localhost/api/invoices?page=0&size=20>; rel="last",<http://localhost/api/invoices?page=0&size=20>; rel="first"',
              },
              body: [invoice],
            },
          ).as('entitiesRequestInternal');
        });

        cy.visit(invoicePageUrl);

        cy.wait('@entitiesRequestInternal');
      });

      it('detail button click should load details Invoice page', () => {
        cy.get(entityDetailsButtonSelector).first().click();
        cy.getEntityDetailsHeading('invoice');
        cy.get(entityDetailsBackButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', invoicePageUrlPattern);
      });

      it('edit button click should load edit Invoice page and go back', () => {
        cy.get(entityEditButtonSelector).first().click();
        cy.getEntityCreateUpdateHeading('Invoice');
        cy.get(entityCreateSaveButtonSelector).should('exist');
        cy.get(entityCreateCancelButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', invoicePageUrlPattern);
      });

      it('edit button click should load edit Invoice page and save', () => {
        cy.get(entityEditButtonSelector).first().click();
        cy.getEntityCreateUpdateHeading('Invoice');
        cy.get(entityCreateSaveButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', invoicePageUrlPattern);
      });

      it('last delete button click should delete instance of Invoice', () => {
        cy.get(entityDeleteButtonSelector).last().click();
        cy.getEntityDeleteDialogHeading('invoice').should('exist');
        cy.get(entityConfirmDeleteButtonSelector).click();
        cy.wait('@deleteEntityRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(204);
        });
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', invoicePageUrlPattern);

        invoice = undefined;
      });
    });
  });

  describe('new Invoice page', () => {
    beforeEach(() => {
      cy.visit(`${invoicePageUrl}`);
      cy.get(entityCreateButtonSelector).click();
      cy.getEntityCreateUpdateHeading('Invoice');
    });

    it('should create an instance of Invoice', () => {
      cy.get(`[data-cy="code"]`).type('huzzah minus popularity');
      cy.get(`[data-cy="code"]`).should('have.value', 'huzzah minus popularity');

      cy.get(`[data-cy="date"]`).type('2026-06-15T14:10');
      cy.get(`[data-cy="date"]`).blur();
      cy.get(`[data-cy="date"]`).should('have.value', '2026-06-15T14:10');

      cy.get(`[data-cy="amount"]`).type('30551.01');
      cy.get(`[data-cy="amount"]`).should('have.value', '30551.01');

      cy.get(`[data-cy="status"]`).select('CANCELLED');

      cy.get(entityCreateSaveButtonSelector).click();

      cy.wait('@postEntityRequest').then(({ response }) => {
        expect(response?.statusCode).to.equal(201);
        invoice = response.body;
      });
      cy.wait('@entitiesRequest').then(({ response }) => {
        expect(response?.statusCode).to.equal(200);
      });
      cy.url().should('match', invoicePageUrlPattern);
    });
  });
});
