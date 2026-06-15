import dayjs from 'dayjs/esm';
import { InvoiceStatus } from 'app/entities/enumerations/invoice-status.model';

export interface IInvoice {
  id: number;
  code?: string | null;
  date?: dayjs.Dayjs | null;
  amount?: number | null;
  status?: keyof typeof InvoiceStatus | null;
}

export type NewInvoice = Omit<IInvoice, 'id'> & { id: null };
