import { ICustomer } from 'app/entities/customer/customer.model';

export interface IOwner {
  id: number;
  address?: string | null;
  city?: string | null;
  telephone?: string | null;
  customer?: Pick<ICustomer, 'id'> | null;
}

export type NewOwner = Omit<IOwner, 'id'> & { id: null };
