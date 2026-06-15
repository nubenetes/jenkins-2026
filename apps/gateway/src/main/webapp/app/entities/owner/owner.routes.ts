import { Routes } from '@angular/router';

import { UserRouteAccessService } from 'app/core/auth/user-route-access.service';
import { ASC } from 'app/config/navigation.constants';
import OwnerResolve from './route/owner-routing-resolve.service';

const ownerRoute: Routes = [
  {
    path: '',
    loadComponent: () => import('./list/owner.component').then(m => m.OwnerComponent),
    data: {
      defaultSort: `id,${ASC}`,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/view',
    loadComponent: () => import('./detail/owner-detail.component').then(m => m.OwnerDetailComponent),
    resolve: {
      owner: OwnerResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: 'new',
    loadComponent: () => import('./update/owner-update.component').then(m => m.OwnerUpdateComponent),
    resolve: {
      owner: OwnerResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/edit',
    loadComponent: () => import('./update/owner-update.component').then(m => m.OwnerUpdateComponent),
    resolve: {
      owner: OwnerResolve,
    },
    canActivate: [UserRouteAccessService],
  },
];

export default ownerRoute;
