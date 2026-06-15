import { inject } from '@angular/core';
import { HttpResponse } from '@angular/common/http';
import { ActivatedRouteSnapshot, Router } from '@angular/router';
import { EMPTY, Observable, of } from 'rxjs';
import { mergeMap } from 'rxjs/operators';

import { IPayment } from '../payment.model';
import { PaymentService } from '../service/payment.service';

const paymentResolve = (route: ActivatedRouteSnapshot): Observable<null | IPayment> => {
  const id = route.params.id;
  if (id) {
    return inject(PaymentService)
      .find(id)
      .pipe(
        mergeMap((payment: HttpResponse<IPayment>) => {
          if (payment.body) {
            return of(payment.body);
          }
          inject(Router).navigate(['404']);
          return EMPTY;
        }),
      );
  }
  return of(null);
};

export default paymentResolve;
