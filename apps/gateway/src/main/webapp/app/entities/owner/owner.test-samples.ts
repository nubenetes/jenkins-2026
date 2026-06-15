import { IOwner, NewOwner } from './owner.model';

export const sampleWithRequiredData: IOwner = {
  id: 6021,
};

export const sampleWithPartialData: IOwner = {
  id: 2591,
  address: 'instead self-reliant anti',
};

export const sampleWithFullData: IOwner = {
  id: 18922,
  address: 'till quiet',
  city: 'Port Reva',
  telephone: '426-681-2642 x1752',
};

export const sampleWithNewData: NewOwner = {
  id: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
