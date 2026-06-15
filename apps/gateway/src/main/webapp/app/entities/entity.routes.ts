import { Routes } from '@angular/router';

const routes: Routes = [
  {
    path: 'authority',
    data: { pageTitle: 'gatewayApp.adminAuthority.home.title' },
    loadChildren: () => import('./admin/authority/authority.routes'),
  },
  {
    path: 'customer',
    data: { pageTitle: 'gatewayApp.customer.home.title' },
    loadChildren: () => import('./customer/customer.routes'),
  },
  {
    path: 'owner',
    data: { pageTitle: 'gatewayApp.owner.home.title' },
    loadChildren: () => import('./owner/owner.routes'),
  },
  {
    path: 'pet',
    data: { pageTitle: 'gatewayApp.pet.home.title' },
    loadChildren: () => import('./pet/pet.routes'),
  },
  {
    path: 'invoice',
    data: { pageTitle: 'gatewayApp.invoice.home.title' },
    loadChildren: () => import('./invoice/invoice.routes'),
  },
  {
    path: 'payment',
    data: { pageTitle: 'gatewayApp.payment.home.title' },
    loadChildren: () => import('./payment/payment.routes'),
  },
  /* jhipster-needle-add-entity-route - JHipster will add entity modules routes here */
];

export default routes;
