import { Component, OnInit, inject } from '@angular/core';
import { HttpResponse } from '@angular/common/http';
import { ActivatedRoute } from '@angular/router';
import { Observable } from 'rxjs';
import { finalize, map } from 'rxjs/operators';

import SharedModule from 'app/shared/shared.module';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';

import { ICustomer } from 'app/entities/customer/customer.model';
import { CustomerService } from 'app/entities/customer/service/customer.service';
import { IOwner } from '../owner.model';
import { OwnerService } from '../service/owner.service';
import { OwnerFormGroup, OwnerFormService } from './owner-form.service';

@Component({
  standalone: true,
  selector: 'jhi-owner-update',
  templateUrl: './owner-update.component.html',
  imports: [SharedModule, FormsModule, ReactiveFormsModule],
})
export class OwnerUpdateComponent implements OnInit {
  isSaving = false;
  owner: IOwner | null = null;

  customersCollection: ICustomer[] = [];

  protected ownerService = inject(OwnerService);
  protected ownerFormService = inject(OwnerFormService);
  protected customerService = inject(CustomerService);
  protected activatedRoute = inject(ActivatedRoute);

  // eslint-disable-next-line @typescript-eslint/member-ordering
  editForm: OwnerFormGroup = this.ownerFormService.createOwnerFormGroup();

  compareCustomer = (o1: ICustomer | null, o2: ICustomer | null): boolean => this.customerService.compareCustomer(o1, o2);

  ngOnInit(): void {
    this.activatedRoute.data.subscribe(({ owner }) => {
      this.owner = owner;
      if (owner) {
        this.updateForm(owner);
      }

      this.loadRelationshipsOptions();
    });
  }

  previousState(): void {
    window.history.back();
  }

  save(): void {
    this.isSaving = true;
    const owner = this.ownerFormService.getOwner(this.editForm);
    if (owner.id !== null) {
      this.subscribeToSaveResponse(this.ownerService.update(owner));
    } else {
      this.subscribeToSaveResponse(this.ownerService.create(owner));
    }
  }

  protected subscribeToSaveResponse(result: Observable<HttpResponse<IOwner>>): void {
    result.pipe(finalize(() => this.onSaveFinalize())).subscribe({
      next: () => this.onSaveSuccess(),
      error: () => this.onSaveError(),
    });
  }

  protected onSaveSuccess(): void {
    this.previousState();
  }

  protected onSaveError(): void {
    // Api for inheritance.
  }

  protected onSaveFinalize(): void {
    this.isSaving = false;
  }

  protected updateForm(owner: IOwner): void {
    this.owner = owner;
    this.ownerFormService.resetForm(this.editForm, owner);

    this.customersCollection = this.customerService.addCustomerToCollectionIfMissing<ICustomer>(this.customersCollection, owner.customer);
  }

  protected loadRelationshipsOptions(): void {
    this.customerService
      .query({ filter: 'owner-is-null' })
      .pipe(map((res: HttpResponse<ICustomer[]>) => res.body ?? []))
      .pipe(
        map((customers: ICustomer[]) => this.customerService.addCustomerToCollectionIfMissing<ICustomer>(customers, this.owner?.customer)),
      )
      .subscribe((customers: ICustomer[]) => (this.customersCollection = customers));
  }
}
