import { TestBed } from '@angular/core/testing';

import { sampleWithNewData, sampleWithRequiredData } from '../owner.test-samples';

import { OwnerFormService } from './owner-form.service';

describe('Owner Form Service', () => {
  let service: OwnerFormService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(OwnerFormService);
  });

  describe('Service methods', () => {
    describe('createOwnerFormGroup', () => {
      it('should create a new form with FormControl', () => {
        const formGroup = service.createOwnerFormGroup();

        expect(formGroup.controls).toEqual(
          expect.objectContaining({
            id: expect.any(Object),
            address: expect.any(Object),
            city: expect.any(Object),
            telephone: expect.any(Object),
            customer: expect.any(Object),
          }),
        );
      });

      it('passing IOwner should create a new form with FormGroup', () => {
        const formGroup = service.createOwnerFormGroup(sampleWithRequiredData);

        expect(formGroup.controls).toEqual(
          expect.objectContaining({
            id: expect.any(Object),
            address: expect.any(Object),
            city: expect.any(Object),
            telephone: expect.any(Object),
            customer: expect.any(Object),
          }),
        );
      });
    });

    describe('getOwner', () => {
      it('should return NewOwner for default Owner initial value', () => {
        const formGroup = service.createOwnerFormGroup(sampleWithNewData);

        const owner = service.getOwner(formGroup) as any;

        expect(owner).toMatchObject(sampleWithNewData);
      });

      it('should return NewOwner for empty Owner initial value', () => {
        const formGroup = service.createOwnerFormGroup();

        const owner = service.getOwner(formGroup) as any;

        expect(owner).toMatchObject({});
      });

      it('should return IOwner', () => {
        const formGroup = service.createOwnerFormGroup(sampleWithRequiredData);

        const owner = service.getOwner(formGroup) as any;

        expect(owner).toMatchObject(sampleWithRequiredData);
      });
    });

    describe('resetForm', () => {
      it('passing IOwner should not enable id FormControl', () => {
        const formGroup = service.createOwnerFormGroup();
        expect(formGroup.controls.id.disabled).toBe(true);

        service.resetForm(formGroup, sampleWithRequiredData);

        expect(formGroup.controls.id.disabled).toBe(true);
      });

      it('passing NewOwner should disable id FormControl', () => {
        const formGroup = service.createOwnerFormGroup(sampleWithRequiredData);
        expect(formGroup.controls.id.disabled).toBe(true);

        service.resetForm(formGroup, { id: null });

        expect(formGroup.controls.id.disabled).toBe(true);
      });
    });
  });
});
