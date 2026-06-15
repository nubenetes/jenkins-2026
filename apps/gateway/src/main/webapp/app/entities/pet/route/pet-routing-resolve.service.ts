import { inject } from '@angular/core';
import { HttpResponse } from '@angular/common/http';
import { ActivatedRouteSnapshot, Router } from '@angular/router';
import { EMPTY, Observable, of } from 'rxjs';
import { mergeMap } from 'rxjs/operators';

import { IPet } from '../pet.model';
import { PetService } from '../service/pet.service';

const petResolve = (route: ActivatedRouteSnapshot): Observable<null | IPet> => {
  const id = route.params.id;
  if (id) {
    return inject(PetService)
      .find(id)
      .pipe(
        mergeMap((pet: HttpResponse<IPet>) => {
          if (pet.body) {
            return of(pet.body);
          }
          inject(Router).navigate(['404']);
          return EMPTY;
        }),
      );
  }
  return of(null);
};

export default petResolve;
