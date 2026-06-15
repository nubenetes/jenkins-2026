import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HttpResponse, provideHttpClient } from '@angular/common/http';
import { FormBuilder } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { Subject, from, of } from 'rxjs';

import { ICustomer } from 'app/entities/customer/customer.model';
import { CustomerService } from 'app/entities/customer/service/customer.service';
import { OwnerService } from '../service/owner.service';
import { IOwner } from '../owner.model';
import { OwnerFormService } from './owner-form.service';

import { OwnerUpdateComponent } from './owner-update.component';

describe('Owner Management Update Component', () => {
  let comp: OwnerUpdateComponent;
  let fixture: ComponentFixture<OwnerUpdateComponent>;
  let activatedRoute: ActivatedRoute;
  let ownerFormService: OwnerFormService;
  let ownerService: OwnerService;
  let customerService: CustomerService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [OwnerUpdateComponent],
      providers: [
        provideHttpClient(),
        FormBuilder,
        {
          provide: ActivatedRoute,
          useValue: {
            params: from([{}]),
          },
        },
      ],
    })
      .overrideTemplate(OwnerUpdateComponent, '')
      .compileComponents();

    fixture = TestBed.createComponent(OwnerUpdateComponent);
    activatedRoute = TestBed.inject(ActivatedRoute);
    ownerFormService = TestBed.inject(OwnerFormService);
    ownerService = TestBed.inject(OwnerService);
    customerService = TestBed.inject(CustomerService);

    comp = fixture.componentInstance;
  });

  describe('ngOnInit', () => {
    it('Should call customer query and add missing value', () => {
      const owner: IOwner = { id: 456 };
      const customer: ICustomer = { id: 13892 };
      owner.customer = customer;

      const customerCollection: ICustomer[] = [{ id: 20336 }];
      jest.spyOn(customerService, 'query').mockReturnValue(of(new HttpResponse({ body: customerCollection })));
      const expectedCollection: ICustomer[] = [customer, ...customerCollection];
      jest.spyOn(customerService, 'addCustomerToCollectionIfMissing').mockReturnValue(expectedCollection);

      activatedRoute.data = of({ owner });
      comp.ngOnInit();

      expect(customerService.query).toHaveBeenCalled();
      expect(customerService.addCustomerToCollectionIfMissing).toHaveBeenCalledWith(customerCollection, customer);
      expect(comp.customersCollection).toEqual(expectedCollection);
    });

    it('Should update editForm', () => {
      const owner: IOwner = { id: 456 };
      const customer: ICustomer = { id: 10490 };
      owner.customer = customer;

      activatedRoute.data = of({ owner });
      comp.ngOnInit();

      expect(comp.customersCollection).toContain(customer);
      expect(comp.owner).toEqual(owner);
    });
  });

  describe('save', () => {
    it('Should call update service on save for existing entity', () => {
      // GIVEN
      const saveSubject = new Subject<HttpResponse<IOwner>>();
      const owner = { id: 123 };
      jest.spyOn(ownerFormService, 'getOwner').mockReturnValue(owner);
      jest.spyOn(ownerService, 'update').mockReturnValue(saveSubject);
      jest.spyOn(comp, 'previousState');
      activatedRoute.data = of({ owner });
      comp.ngOnInit();

      // WHEN
      comp.save();
      expect(comp.isSaving).toEqual(true);
      saveSubject.next(new HttpResponse({ body: owner }));
      saveSubject.complete();

      // THEN
      expect(ownerFormService.getOwner).toHaveBeenCalled();
      expect(comp.previousState).toHaveBeenCalled();
      expect(ownerService.update).toHaveBeenCalledWith(expect.objectContaining(owner));
      expect(comp.isSaving).toEqual(false);
    });

    it('Should call create service on save for new entity', () => {
      // GIVEN
      const saveSubject = new Subject<HttpResponse<IOwner>>();
      const owner = { id: 123 };
      jest.spyOn(ownerFormService, 'getOwner').mockReturnValue({ id: null });
      jest.spyOn(ownerService, 'create').mockReturnValue(saveSubject);
      jest.spyOn(comp, 'previousState');
      activatedRoute.data = of({ owner: null });
      comp.ngOnInit();

      // WHEN
      comp.save();
      expect(comp.isSaving).toEqual(true);
      saveSubject.next(new HttpResponse({ body: owner }));
      saveSubject.complete();

      // THEN
      expect(ownerFormService.getOwner).toHaveBeenCalled();
      expect(ownerService.create).toHaveBeenCalled();
      expect(comp.isSaving).toEqual(false);
      expect(comp.previousState).toHaveBeenCalled();
    });

    it('Should set isSaving to false on error', () => {
      // GIVEN
      const saveSubject = new Subject<HttpResponse<IOwner>>();
      const owner = { id: 123 };
      jest.spyOn(ownerService, 'update').mockReturnValue(saveSubject);
      jest.spyOn(comp, 'previousState');
      activatedRoute.data = of({ owner });
      comp.ngOnInit();

      // WHEN
      comp.save();
      expect(comp.isSaving).toEqual(true);
      saveSubject.error('This is an error!');

      // THEN
      expect(ownerService.update).toHaveBeenCalled();
      expect(comp.isSaving).toEqual(false);
      expect(comp.previousState).not.toHaveBeenCalled();
    });
  });

  describe('Compare relationships', () => {
    describe('compareCustomer', () => {
      it('Should forward to customerService', () => {
        const entity = { id: 123 };
        const entity2 = { id: 456 };
        jest.spyOn(customerService, 'compareCustomer');
        comp.compareCustomer(entity, entity2);
        expect(customerService.compareCustomer).toHaveBeenCalledWith(entity, entity2);
      });
    });
  });
});
