import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpResponse } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import dayjs from 'dayjs/esm';

import { isPresent } from 'app/core/util/operators';
import { DATE_FORMAT } from 'app/config/input.constants';
import { ApplicationConfigService } from 'app/core/config/application-config.service';
import { createRequestOption } from 'app/core/request/request-util';
import { IPet, NewPet } from '../pet.model';

export type PartialUpdatePet = Partial<IPet> & Pick<IPet, 'id'>;

type RestOf<T extends IPet | NewPet> = Omit<T, 'birthDate'> & {
  birthDate?: string | null;
};

export type RestPet = RestOf<IPet>;

export type NewRestPet = RestOf<NewPet>;

export type PartialUpdateRestPet = RestOf<PartialUpdatePet>;

export type EntityResponseType = HttpResponse<IPet>;
export type EntityArrayResponseType = HttpResponse<IPet[]>;

@Injectable({ providedIn: 'root' })
export class PetService {
  protected readonly http = inject(HttpClient);
  protected readonly applicationConfigService = inject(ApplicationConfigService);

  protected resourceUrl = this.applicationConfigService.getEndpointFor('api/pets');

  create(pet: NewPet): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(pet);
    return this.http.post<RestPet>(this.resourceUrl, copy, { observe: 'response' }).pipe(map(res => this.convertResponseFromServer(res)));
  }

  update(pet: IPet): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(pet);
    return this.http
      .put<RestPet>(`${this.resourceUrl}/${this.getPetIdentifier(pet)}`, copy, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  partialUpdate(pet: PartialUpdatePet): Observable<EntityResponseType> {
    const copy = this.convertDateFromClient(pet);
    return this.http
      .patch<RestPet>(`${this.resourceUrl}/${this.getPetIdentifier(pet)}`, copy, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  find(id: number): Observable<EntityResponseType> {
    return this.http
      .get<RestPet>(`${this.resourceUrl}/${id}`, { observe: 'response' })
      .pipe(map(res => this.convertResponseFromServer(res)));
  }

  query(req?: any): Observable<EntityArrayResponseType> {
    const options = createRequestOption(req);
    return this.http
      .get<RestPet[]>(this.resourceUrl, { params: options, observe: 'response' })
      .pipe(map(res => this.convertResponseArrayFromServer(res)));
  }

  delete(id: number): Observable<HttpResponse<{}>> {
    return this.http.delete(`${this.resourceUrl}/${id}`, { observe: 'response' });
  }

  getPetIdentifier(pet: Pick<IPet, 'id'>): number {
    return pet.id;
  }

  comparePet(o1: Pick<IPet, 'id'> | null, o2: Pick<IPet, 'id'> | null): boolean {
    return o1 && o2 ? this.getPetIdentifier(o1) === this.getPetIdentifier(o2) : o1 === o2;
  }

  addPetToCollectionIfMissing<Type extends Pick<IPet, 'id'>>(petCollection: Type[], ...petsToCheck: (Type | null | undefined)[]): Type[] {
    const pets: Type[] = petsToCheck.filter(isPresent);
    if (pets.length > 0) {
      const petCollectionIdentifiers = petCollection.map(petItem => this.getPetIdentifier(petItem));
      const petsToAdd = pets.filter(petItem => {
        const petIdentifier = this.getPetIdentifier(petItem);
        if (petCollectionIdentifiers.includes(petIdentifier)) {
          return false;
        }
        petCollectionIdentifiers.push(petIdentifier);
        return true;
      });
      return [...petsToAdd, ...petCollection];
    }
    return petCollection;
  }

  protected convertDateFromClient<T extends IPet | NewPet | PartialUpdatePet>(pet: T): RestOf<T> {
    return {
      ...pet,
      birthDate: pet.birthDate?.format(DATE_FORMAT) ?? null,
    };
  }

  protected convertDateFromServer(restPet: RestPet): IPet {
    return {
      ...restPet,
      birthDate: restPet.birthDate ? dayjs(restPet.birthDate) : undefined,
    };
  }

  protected convertResponseFromServer(res: HttpResponse<RestPet>): HttpResponse<IPet> {
    return res.clone({
      body: res.body ? this.convertDateFromServer(res.body) : null,
    });
  }

  protected convertResponseArrayFromServer(res: HttpResponse<RestPet[]>): HttpResponse<IPet[]> {
    return res.clone({
      body: res.body ? res.body.map(item => this.convertDateFromServer(item)) : null,
    });
  }
}
