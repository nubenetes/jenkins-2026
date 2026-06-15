import { TestBed } from '@angular/core/testing';

import { sampleWithNewData, sampleWithRequiredData } from '../pet.test-samples';

import { PetFormService } from './pet-form.service';

describe('Pet Form Service', () => {
  let service: PetFormService;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(PetFormService);
  });

  describe('Service methods', () => {
    describe('createPetFormGroup', () => {
      it('should create a new form with FormControl', () => {
        const formGroup = service.createPetFormGroup();

        expect(formGroup.controls).toEqual(
          expect.objectContaining({
            id: expect.any(Object),
            name: expect.any(Object),
            birthDate: expect.any(Object),
            owner: expect.any(Object),
          }),
        );
      });

      it('passing IPet should create a new form with FormGroup', () => {
        const formGroup = service.createPetFormGroup(sampleWithRequiredData);

        expect(formGroup.controls).toEqual(
          expect.objectContaining({
            id: expect.any(Object),
            name: expect.any(Object),
            birthDate: expect.any(Object),
            owner: expect.any(Object),
          }),
        );
      });
    });

    describe('getPet', () => {
      it('should return NewPet for default Pet initial value', () => {
        const formGroup = service.createPetFormGroup(sampleWithNewData);

        const pet = service.getPet(formGroup) as any;

        expect(pet).toMatchObject(sampleWithNewData);
      });

      it('should return NewPet for empty Pet initial value', () => {
        const formGroup = service.createPetFormGroup();

        const pet = service.getPet(formGroup) as any;

        expect(pet).toMatchObject({});
      });

      it('should return IPet', () => {
        const formGroup = service.createPetFormGroup(sampleWithRequiredData);

        const pet = service.getPet(formGroup) as any;

        expect(pet).toMatchObject(sampleWithRequiredData);
      });
    });

    describe('resetForm', () => {
      it('passing IPet should not enable id FormControl', () => {
        const formGroup = service.createPetFormGroup();
        expect(formGroup.controls.id.disabled).toBe(true);

        service.resetForm(formGroup, sampleWithRequiredData);

        expect(formGroup.controls.id.disabled).toBe(true);
      });

      it('passing NewPet should disable id FormControl', () => {
        const formGroup = service.createPetFormGroup(sampleWithRequiredData);
        expect(formGroup.controls.id.disabled).toBe(true);

        service.resetForm(formGroup, { id: null });

        expect(formGroup.controls.id.disabled).toBe(true);
      });
    });
  });
});
