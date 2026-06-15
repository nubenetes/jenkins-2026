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

describe('Pet e2e test', () => {
  const petPageUrl = '/pet';
  const petPageUrlPattern = new RegExp('/pet(\\?.*)?$');
  const username = Cypress.env('E2E_USERNAME') ?? 'user';
  const password = Cypress.env('E2E_PASSWORD') ?? 'user';
  const petSample = { name: 'rival plagiarise' };

  let pet;

  beforeEach(() => {
    cy.login(username, password);
  });

  beforeEach(() => {
    cy.intercept('GET', '/api/pets+(?*|)').as('entitiesRequest');
    cy.intercept('POST', '/api/pets').as('postEntityRequest');
    cy.intercept('DELETE', '/api/pets/*').as('deleteEntityRequest');
  });

  afterEach(() => {
    if (pet) {
      cy.authenticatedRequest({
        method: 'DELETE',
        url: `/api/pets/${pet.id}`,
      }).then(() => {
        pet = undefined;
      });
    }
  });

  it('Pets menu should load Pets page', () => {
    cy.visit('/');
    cy.clickOnEntityMenuItem('pet');
    cy.wait('@entitiesRequest').then(({ response }) => {
      if (response?.body.length === 0) {
        cy.get(entityTableSelector).should('not.exist');
      } else {
        cy.get(entityTableSelector).should('exist');
      }
    });
    cy.getEntityHeading('Pet').should('exist');
    cy.url().should('match', petPageUrlPattern);
  });

  describe('Pet page', () => {
    describe('create button click', () => {
      beforeEach(() => {
        cy.visit(petPageUrl);
        cy.wait('@entitiesRequest');
      });

      it('should load create Pet page', () => {
        cy.get(entityCreateButtonSelector).click();
        cy.url().should('match', new RegExp('/pet/new$'));
        cy.getEntityCreateUpdateHeading('Pet');
        cy.get(entityCreateSaveButtonSelector).should('exist');
        cy.get(entityCreateCancelButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', petPageUrlPattern);
      });
    });

    describe('with existing value', () => {
      beforeEach(() => {
        cy.authenticatedRequest({
          method: 'POST',
          url: '/api/pets',
          body: petSample,
        }).then(({ body }) => {
          pet = body;

          cy.intercept(
            {
              method: 'GET',
              url: '/api/pets+(?*|)',
              times: 1,
            },
            {
              statusCode: 200,
              body: [pet],
            },
          ).as('entitiesRequestInternal');
        });

        cy.visit(petPageUrl);

        cy.wait('@entitiesRequestInternal');
      });

      it('detail button click should load details Pet page', () => {
        cy.get(entityDetailsButtonSelector).first().click();
        cy.getEntityDetailsHeading('pet');
        cy.get(entityDetailsBackButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', petPageUrlPattern);
      });

      it('edit button click should load edit Pet page and go back', () => {
        cy.get(entityEditButtonSelector).first().click();
        cy.getEntityCreateUpdateHeading('Pet');
        cy.get(entityCreateSaveButtonSelector).should('exist');
        cy.get(entityCreateCancelButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', petPageUrlPattern);
      });

      it('edit button click should load edit Pet page and save', () => {
        cy.get(entityEditButtonSelector).first().click();
        cy.getEntityCreateUpdateHeading('Pet');
        cy.get(entityCreateSaveButtonSelector).click();
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', petPageUrlPattern);
      });

      it('last delete button click should delete instance of Pet', () => {
        cy.get(entityDeleteButtonSelector).last().click();
        cy.getEntityDeleteDialogHeading('pet').should('exist');
        cy.get(entityConfirmDeleteButtonSelector).click();
        cy.wait('@deleteEntityRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(204);
        });
        cy.wait('@entitiesRequest').then(({ response }) => {
          expect(response?.statusCode).to.equal(200);
        });
        cy.url().should('match', petPageUrlPattern);

        pet = undefined;
      });
    });
  });

  describe('new Pet page', () => {
    beforeEach(() => {
      cy.visit(`${petPageUrl}`);
      cy.get(entityCreateButtonSelector).click();
      cy.getEntityCreateUpdateHeading('Pet');
    });

    it('should create an instance of Pet', () => {
      cy.get(`[data-cy="name"]`).type('bah uneven french');
      cy.get(`[data-cy="name"]`).should('have.value', 'bah uneven french');

      cy.get(`[data-cy="birthDate"]`).type('2026-06-15');
      cy.get(`[data-cy="birthDate"]`).blur();
      cy.get(`[data-cy="birthDate"]`).should('have.value', '2026-06-15');

      cy.get(entityCreateSaveButtonSelector).click();

      cy.wait('@postEntityRequest').then(({ response }) => {
        expect(response?.statusCode).to.equal(201);
        pet = response.body;
      });
      cy.wait('@entitiesRequest').then(({ response }) => {
        expect(response?.statusCode).to.equal(200);
      });
      cy.url().should('match', petPageUrlPattern);
    });
  });
});
