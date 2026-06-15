import { ICustomer, NewCustomer } from './customer.model';

export const sampleWithRequiredData: ICustomer = {
  id: 10131,
  firstName: 'Braden',
  lastName: 'Nicolas',
  email: "/@#z'c?6.6}A",
};

export const sampleWithPartialData: ICustomer = {
  id: 11414,
  firstName: 'Neal',
  lastName: 'Kulas',
  email: '!rCc@BKX%.cxn',
};

export const sampleWithFullData: ICustomer = {
  id: 2783,
  firstName: 'Kaia',
  lastName: 'Stokes',
  email: 'mM|T*@RMZwU.5',
};

export const sampleWithNewData: NewCustomer = {
  firstName: 'Kurt',
  lastName: 'Leuschke',
  email: 'Kf!0U@|-.v4hL4/',
  id: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
