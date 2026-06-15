import dayjs from 'dayjs/esm';

import { IInvoice, NewInvoice } from './invoice.model';

export const sampleWithRequiredData: IInvoice = {
  id: 935,
  code: 'nor',
  date: dayjs('2026-06-14T17:54'),
  amount: 17728.81,
  status: 'PAID',
};

export const sampleWithPartialData: IInvoice = {
  id: 13438,
  code: 'prance handover guilty',
  date: dayjs('2026-06-15T14:07'),
  amount: 23864.29,
  status: 'ISSUED',
};

export const sampleWithFullData: IInvoice = {
  id: 12508,
  code: 'dock',
  date: dayjs('2026-06-15T13:10'),
  amount: 25882.16,
  status: 'ISSUED',
};

export const sampleWithNewData: NewInvoice = {
  code: 'abaft buzzing',
  date: dayjs('2026-06-15T08:28'),
  amount: 3449.86,
  status: 'CANCELLED',
  id: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
