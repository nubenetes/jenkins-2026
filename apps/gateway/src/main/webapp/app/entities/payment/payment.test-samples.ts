import dayjs from 'dayjs/esm';

import { IPayment, NewPayment } from './payment.model';

export const sampleWithRequiredData: IPayment = {
  id: 13010,
  amount: 10712.83,
  paymentDate: dayjs('2026-06-15T15:04'),
  method: 'BANK_TRANSFER',
};

export const sampleWithPartialData: IPayment = {
  id: 22874,
  amount: 24368.45,
  paymentDate: dayjs('2026-06-15T13:04'),
  method: 'BANK_TRANSFER',
};

export const sampleWithFullData: IPayment = {
  id: 10684,
  amount: 13015.95,
  paymentDate: dayjs('2026-06-14T20:19'),
  method: 'CASH',
};

export const sampleWithNewData: NewPayment = {
  amount: 13539.43,
  paymentDate: dayjs('2026-06-15T02:08'),
  method: 'CASH',
  id: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
