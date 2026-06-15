import NavbarItem from 'app/layouts/navbar/navbar-item.model';

export const EntityNavbarItems: NavbarItem[] = [
  {
    name: 'Customer',
    route: '/customer',
    translationKey: 'global.menu.entities.customer',
  },
  {
    name: 'Owner',
    route: '/owner',
    translationKey: 'global.menu.entities.owner',
  },
  {
    name: 'Pet',
    route: '/pet',
    translationKey: 'global.menu.entities.pet',
  },
  {
    name: 'Invoice',
    route: '/invoice',
    translationKey: 'global.menu.entities.invoice',
  },
  {
    name: 'Payment',
    route: '/payment',
    translationKey: 'global.menu.entities.payment',
  },
];
