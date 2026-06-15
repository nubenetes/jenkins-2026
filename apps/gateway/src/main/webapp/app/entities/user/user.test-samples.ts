import { IUser } from './user.model';

export const sampleWithRequiredData: IUser = {
  id: 8406,
  login: 'P',
};

export const sampleWithPartialData: IUser = {
  id: 2543,
  login: 'MQ@6Eh\\GT\\&5\\#CKEm\\CDLkD',
};

export const sampleWithFullData: IUser = {
  id: 28666,
  login: 'SvaA5U',
};
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
