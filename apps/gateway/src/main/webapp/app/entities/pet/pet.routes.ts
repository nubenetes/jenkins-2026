import { Routes } from '@angular/router';

import { UserRouteAccessService } from 'app/core/auth/user-route-access.service';
import { ASC } from 'app/config/navigation.constants';
import PetResolve from './route/pet-routing-resolve.service';

const petRoute: Routes = [
  {
    path: '',
    loadComponent: () => import('./list/pet.component').then(m => m.PetComponent),
    data: {
      defaultSort: `id,${ASC}`,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/view',
    loadComponent: () => import('./detail/pet-detail.component').then(m => m.PetDetailComponent),
    resolve: {
      pet: PetResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: 'new',
    loadComponent: () => import('./update/pet-update.component').then(m => m.PetUpdateComponent),
    resolve: {
      pet: PetResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/edit',
    loadComponent: () => import('./update/pet-update.component').then(m => m.PetUpdateComponent),
    resolve: {
      pet: PetResolve,
    },
    canActivate: [UserRouteAccessService],
  },
];

export default petRoute;
