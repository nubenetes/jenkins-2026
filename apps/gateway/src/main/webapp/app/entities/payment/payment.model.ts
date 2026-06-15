import dayjs from 'dayjs/esm';
import { IInvoice } from 'app/entities/invoice/invoice.model';
import { PaymentMethod } from 'app/entities/enumerations/payment-method.model';

export interface IPayment {
  id: number;
  amount?: number | null;
  paymentDate?: dayjs.Dayjs | null;
  method?: keyof typeof PaymentMethod | null;
  invoice?: Pick<IInvoice, 'id'> | null;
}

export type NewPayment = Omit<IPayment, 'id'> & { id: null };
