import { TestBed } from '@angular/core/testing';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';

import { DATE_FORMAT } from 'app/config/input.constants';
import { IPet } from '../pet.model';
import { sampleWithFullData, sampleWithNewData, sampleWithPartialData, sampleWithRequiredData } from '../pet.test-samples';

import { PetService, RestPet } from './pet.service';

const requireRestSample: RestPet = {
  ...sampleWithRequiredData,
  birthDate: sampleWithRequiredData.birthDate?.format(DATE_FORMAT),
};

describe('Pet Service', () => {
  let service: PetService;
  let httpMock: HttpTestingController;
  let expectedResult: IPet | IPet[] | boolean | null;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    expectedResult = null;
    service = TestBed.inject(PetService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  describe('Service methods', () => {
    it('should find an element', () => {
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.find(123).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'GET' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should create a Pet', () => {
      const pet = { ...sampleWithNewData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.create(pet).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'POST' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should update a Pet', () => {
      const pet = { ...sampleWithRequiredData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.update(pet).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'PUT' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should partial update a Pet', () => {
      const patchObject = { ...sampleWithPartialData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.partialUpdate(patchObject).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'PATCH' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should return a list of Pet', () => {
      const returnedFromService = { ...requireRestSample };

      const expected = { ...sampleWithRequiredData };

      service.query().subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'GET' });
      req.flush([returnedFromService]);
      httpMock.verify();
      expect(expectedResult).toMatchObject([expected]);
    });

    it('should delete a Pet', () => {
      const expected = true;

      service.delete(123).subscribe(resp => (expectedResult = resp.ok));

      const req = httpMock.expectOne({ method: 'DELETE' });
      req.flush({ status: 200 });
      expect(expectedResult).toBe(expected);
    });

    describe('addPetToCollectionIfMissing', () => {
      it('should add a Pet to an empty array', () => {
        const pet: IPet = sampleWithRequiredData;
        expectedResult = service.addPetToCollectionIfMissing([], pet);
        expect(expectedResult).toHaveLength(1);
        expect(expectedResult).toContain(pet);
      });

      it('should not add a Pet to an array that contains it', () => {
        const pet: IPet = sampleWithRequiredData;
        const petCollection: IPet[] = [
          {
            ...pet,
          },
          sampleWithPartialData,
        ];
        expectedResult = service.addPetToCollectionIfMissing(petCollection, pet);
        expect(expectedResult).toHaveLength(2);
      });

      it("should add a Pet to an array that doesn't contain it", () => {
        const pet: IPet = sampleWithRequiredData;
        const petCollection: IPet[] = [sampleWithPartialData];
        expectedResult = service.addPetToCollectionIfMissing(petCollection, pet);
        expect(expectedResult).toHaveLength(2);
        expect(expectedResult).toContain(pet);
      });

      it('should add only unique Pet to an array', () => {
        const petArray: IPet[] = [sampleWithRequiredData, sampleWithPartialData, sampleWithFullData];
        const petCollection: IPet[] = [sampleWithRequiredData];
        expectedResult = service.addPetToCollectionIfMissing(petCollection, ...petArray);
        expect(expectedResult).toHaveLength(3);
      });

      it('should accept varargs', () => {
        const pet: IPet = sampleWithRequiredData;
        const pet2: IPet = sampleWithPartialData;
        expectedResult = service.addPetToCollectionIfMissing([], pet, pet2);
        expect(expectedResult).toHaveLength(2);
        expect(expectedResult).toContain(pet);
        expect(expectedResult).toContain(pet2);
      });

      it('should accept null and undefined values', () => {
        const pet: IPet = sampleWithRequiredData;
        expectedResult = service.addPetToCollectionIfMissing([], null, pet, undefined);
        expect(expectedResult).toHaveLength(1);
        expect(expectedResult).toContain(pet);
      });

      it('should return initial array if no Pet is added', () => {
        const petCollection: IPet[] = [sampleWithRequiredData];
        expectedResult = service.addPetToCollectionIfMissing(petCollection, undefined, null);
        expect(expectedResult).toEqual(petCollection);
      });
    });

    describe('comparePet', () => {
      it('Should return true if both entities are null', () => {
        const entity1 = null;
        const entity2 = null;

        const compareResult = service.comparePet(entity1, entity2);

        expect(compareResult).toEqual(true);
      });

      it('Should return false if one entity is null', () => {
        const entity1 = { id: 123 };
        const entity2 = null;

        const compareResult1 = service.comparePet(entity1, entity2);
        const compareResult2 = service.comparePet(entity2, entity1);

        expect(compareResult1).toEqual(false);
        expect(compareResult2).toEqual(false);
      });

      it('Should return false if primaryKey differs', () => {
        const entity1 = { id: 123 };
        const entity2 = { id: 456 };

        const compareResult1 = service.comparePet(entity1, entity2);
        const compareResult2 = service.comparePet(entity2, entity1);

        expect(compareResult1).toEqual(false);
        expect(compareResult2).toEqual(false);
      });

      it('Should return false if primaryKey matches', () => {
        const entity1 = { id: 123 };
        const entity2 = { id: 123 };

        const compareResult1 = service.comparePet(entity1, entity2);
        const compareResult2 = service.comparePet(entity2, entity1);

        expect(compareResult1).toEqual(true);
        expect(compareResult2).toEqual(true);
      });
    });
  });

  afterEach(() => {
    httpMock.verify();
  });
});
