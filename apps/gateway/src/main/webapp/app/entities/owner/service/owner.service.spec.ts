import { TestBed } from '@angular/core/testing';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';

import { IOwner } from '../owner.model';
import { sampleWithFullData, sampleWithNewData, sampleWithPartialData, sampleWithRequiredData } from '../owner.test-samples';

import { OwnerService } from './owner.service';

const requireRestSample: IOwner = {
  ...sampleWithRequiredData,
};

describe('Owner Service', () => {
  let service: OwnerService;
  let httpMock: HttpTestingController;
  let expectedResult: IOwner | IOwner[] | boolean | null;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    expectedResult = null;
    service = TestBed.inject(OwnerService);
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

    it('should create a Owner', () => {
      const owner = { ...sampleWithNewData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.create(owner).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'POST' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should update a Owner', () => {
      const owner = { ...sampleWithRequiredData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.update(owner).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'PUT' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should partial update a Owner', () => {
      const patchObject = { ...sampleWithPartialData };
      const returnedFromService = { ...requireRestSample };
      const expected = { ...sampleWithRequiredData };

      service.partialUpdate(patchObject).subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'PATCH' });
      req.flush(returnedFromService);
      expect(expectedResult).toMatchObject(expected);
    });

    it('should return a list of Owner', () => {
      const returnedFromService = { ...requireRestSample };

      const expected = { ...sampleWithRequiredData };

      service.query().subscribe(resp => (expectedResult = resp.body));

      const req = httpMock.expectOne({ method: 'GET' });
      req.flush([returnedFromService]);
      httpMock.verify();
      expect(expectedResult).toMatchObject([expected]);
    });

    it('should delete a Owner', () => {
      const expected = true;

      service.delete(123).subscribe(resp => (expectedResult = resp.ok));

      const req = httpMock.expectOne({ method: 'DELETE' });
      req.flush({ status: 200 });
      expect(expectedResult).toBe(expected);
    });

    describe('addOwnerToCollectionIfMissing', () => {
      it('should add a Owner to an empty array', () => {
        const owner: IOwner = sampleWithRequiredData;
        expectedResult = service.addOwnerToCollectionIfMissing([], owner);
        expect(expectedResult).toHaveLength(1);
        expect(expectedResult).toContain(owner);
      });

      it('should not add a Owner to an array that contains it', () => {
        const owner: IOwner = sampleWithRequiredData;
        const ownerCollection: IOwner[] = [
          {
            ...owner,
          },
          sampleWithPartialData,
        ];
        expectedResult = service.addOwnerToCollectionIfMissing(ownerCollection, owner);
        expect(expectedResult).toHaveLength(2);
      });

      it("should add a Owner to an array that doesn't contain it", () => {
        const owner: IOwner = sampleWithRequiredData;
        const ownerCollection: IOwner[] = [sampleWithPartialData];
        expectedResult = service.addOwnerToCollectionIfMissing(ownerCollection, owner);
        expect(expectedResult).toHaveLength(2);
        expect(expectedResult).toContain(owner);
      });

      it('should add only unique Owner to an array', () => {
        const ownerArray: IOwner[] = [sampleWithRequiredData, sampleWithPartialData, sampleWithFullData];
        const ownerCollection: IOwner[] = [sampleWithRequiredData];
        expectedResult = service.addOwnerToCollectionIfMissing(ownerCollection, ...ownerArray);
        expect(expectedResult).toHaveLength(3);
      });

      it('should accept varargs', () => {
        const owner: IOwner = sampleWithRequiredData;
        const owner2: IOwner = sampleWithPartialData;
        expectedResult = service.addOwnerToCollectionIfMissing([], owner, owner2);
        expect(expectedResult).toHaveLength(2);
        expect(expectedResult).toContain(owner);
        expect(expectedResult).toContain(owner2);
      });

      it('should accept null and undefined values', () => {
        const owner: IOwner = sampleWithRequiredData;
        expectedResult = service.addOwnerToCollectionIfMissing([], null, owner, undefined);
        expect(expectedResult).toHaveLength(1);
        expect(expectedResult).toContain(owner);
      });

      it('should return initial array if no Owner is added', () => {
        const ownerCollection: IOwner[] = [sampleWithRequiredData];
        expectedResult = service.addOwnerToCollectionIfMissing(ownerCollection, undefined, null);
        expect(expectedResult).toEqual(ownerCollection);
      });
    });

    describe('compareOwner', () => {
      it('Should return true if both entities are null', () => {
        const entity1 = null;
        const entity2 = null;

        const compareResult = service.compareOwner(entity1, entity2);

        expect(compareResult).toEqual(true);
      });

      it('Should return false if one entity is null', () => {
        const entity1 = { id: 123 };
        const entity2 = null;

        const compareResult1 = service.compareOwner(entity1, entity2);
        const compareResult2 = service.compareOwner(entity2, entity1);

        expect(compareResult1).toEqual(false);
        expect(compareResult2).toEqual(false);
      });

      it('Should return false if primaryKey differs', () => {
        const entity1 = { id: 123 };
        const entity2 = { id: 456 };

        const compareResult1 = service.compareOwner(entity1, entity2);
        const compareResult2 = service.compareOwner(entity2, entity1);

        expect(compareResult1).toEqual(false);
        expect(compareResult2).toEqual(false);
      });

      it('Should return false if primaryKey matches', () => {
        const entity1 = { id: 123 };
        const entity2 = { id: 123 };

        const compareResult1 = service.compareOwner(entity1, entity2);
        const compareResult2 = service.compareOwner(entity2, entity1);

        expect(compareResult1).toEqual(true);
        expect(compareResult2).toEqual(true);
      });
    });
  });

  afterEach(() => {
    httpMock.verify();
  });
});
