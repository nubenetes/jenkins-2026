import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpResponse } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import dayjs from 'dayjs/esm';

import { isPresent } from 'app/core/util/operators';
import { ApplicationConfigService } from 'app/core/config/application-config.service';
import { createRequestOption } from 'app/core/request/request-util';
import { IPayment, NewPayment } from '../payment.model';

export type PartialUpdatePayment = Partial<IPayment> & Pick<IPayment, 'id'>;

type RestOf<T extends IPayment | NewPayment> = Omit<T, 'paymentDate'> & {
  paymentDate?: string | null;
};

export type RestPayment = RestOf<IPayment>;

export type NewRestPayment = RestOf<NewPayment>;

export type PartialUpdateRestPayment = RestOf<PartialUpdatePayment>;

export type EntityResponseType = HttpResponse<IPayment>;
export type EntityArrayResponseType = HttpResponse<IPayment[]>;

@Injectable({ providedIn: 'root' })
export class PaymentService {
  protected readonly http = inject(HttpClient);
  protected readonly applicationConfigService = inject(ApplicationConfigService);

  protected resourceUrl = this.applicationConfigService.getEndpointFor('api/payments');

  create(payment: NewPayment): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(payment);
    return this.http
      .post<RestPayment>(this.resourceUrl, copy, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  update(payment: IPayment): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(payment);
    return this.http
      .put<RestPayment>(`${this.resourceUrl}/${this.getPaymentIdentifier(payment)}`, copy, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  partialUpdate(payment: PartialUpdatePayment): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(payment);
    return this.http
      .patch<RestPayment>(`${this.resourceUrl}/${this.getPaymentIdentifier(payment)}`, copy, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  find(id: number): Observable<EntityResponseType> {
    return this.http
      .get<RestPayment>(`${this.resourceUrl}/${id}`, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  query(req?: any): Observable<EntityArrayResponseType> {
    const options = createRequestOption(req);
    return this.http
      .get<RestPayment[]>(this.resourceUrl, { params: options, observe: 'response' })
      .pipe(map(res => this.convertResponseArrayFromServer(res)));
  }

  delete(id: number): Observable<HttpResponse<{}>> {
    return this.http.delete(`${this.resourceUrl}/${id}`, { observe: 'response' });
  }

  getPaymentIdentifier(payment: Pick<IPayment, 'id'>): number {
    return payment.id;
  }

  comparePayment(o1: Pick<IPayment, 'id'> | null, o2: Pick<IPayment, 'id'> | null): boolean {
    return o1 && o2 ? this.getPaymentIdentifier(o1) === this.getPaymentIdentifier(o2) : o1 === o2;
  }

  addPaymentToCollectionIfMissing<Type extends Pick<IPayment, 'id'>>(
    paymentCollection: Type[],
    ...paymentsToCheck: (Type | null | undefined)[]
  ): Type[] {
    const payments: Type[] = paymentsToCheck.filter(isPresent);
    if (payments.length > 0) {
      const paymentCollectionIdentifiers = paymentCollection.map(paymentItem => this.getPaymentIdentifier(paymentItem));
      const paymentsToAdd = payments.filter(paymentItem => {
        const paymentIdentifier = this.getPaymentIdentifier(paymentItem);
        if (paymentCollectionIdentifiers.includes(paymentIdentifier)) {
          return false;
        }
        paymentCollectionIdentifiers.push(paymentIdentifier);
        return true;
      });
      return [...paymentsToAdd, ...paymentCollection];
    }
    return paymentCollection;
  }

  protected convertDateFromClient<T extends IPayment | NewPayment | PartialUpdatePayment>(payment: T): RestOf<T> {
    return {
      ...payment,
      paymentDate: payment.paymentDate?.toJSON() ?? null,
    };
  }

  protected convertDateFromServer(restPayment: RestPayment): IPayment {
    return {
      ...restPayment,
      paymentDate: restPayment.paymentDate ? dayjs(restPayment.paymentDate) : undefined,
    };
  }

  protected convertResponseFromServer(res: HttpResponse<RestPayment>): HttpResponse<IPayment> {
    return res.clone({
      body: res.body ? this.convertDateFromServer(res.body) : null,
    });
  }

  protected convertResponseArrayFromServer(res: HttpResponse<RestPayment[]>): HttpResponse<IPayment[]> {
    return res.clone({
      body: res.body ? res.body.map(item => this.convertDateFromServer(item)) : null,
    });
  }
}
