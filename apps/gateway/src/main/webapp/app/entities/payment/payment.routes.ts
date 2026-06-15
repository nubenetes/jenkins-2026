import { Routes } from '@angular/router';

import { UserRouteAccessService } from 'app/core/auth/user-route-access.service';
import { ASC } from 'app/config/navigation.constants';
import PaymentResolve from './route/payment-routing-resolve.service';

const paymentRoute: Routes = [
  {
    path: '',
    loadComponent: () => import('./list/payment.component').then(m => m.PaymentComponent),
    data: {
      defaultSort: `id,${ASC}`,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/view',
    loadComponent: () => import('./detail/payment-detail.component').then(m => m.PaymentDetailComponent),
    resolve: {
      payment: PaymentResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: 'new',
    loadComponent: () => import('./update/payment-update.component').then(m => m.PaymentUpdateComponent),
    resolve: {
      payment: PaymentResolve,
    },
    canActivate: [UserRouteAccessService],
  },
  {
    path: ':id/edit',
    loadComponent: () => import('./update/payment-update.component').then(m => m.PaymentUpdateComponent),
    resolve: {
      payment: PaymentResolve,
    },
    canActivate: [UserRouteAccessService],
  },
];

export default paymentRoute;
