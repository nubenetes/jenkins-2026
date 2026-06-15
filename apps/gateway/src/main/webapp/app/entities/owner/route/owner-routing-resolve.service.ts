import { inject } from '@angular/core';
import { HttpResponse } from '@angular/common/http';
import { ActivatedRouteSnapshot, Router } from '@angular/router';
import { EMPTY, Observable, of } from 'rxjs';
import { mergeMap } from 'rxjs/operators';

import { IOwner } from '../owner.model';
import { OwnerService } from '../service/owner.service';

const ownerResolve = (route: ActivatedRouteSnapshot): Observable<null | IOwner> => {
  const id = route.params.id;
  if (id) {
    return inject(OwnerService)
      .find(id)
      .pipe(
        mergeMap((owner: HttpResponse<IOwner>) => {
          if (owner.body) {
            return of(owner.body);
          }
          inject(Router).navigate(['404']);
          return EMPTY;
        }),
      );
  }
  return of(null);
};

export default ownerResolve;
