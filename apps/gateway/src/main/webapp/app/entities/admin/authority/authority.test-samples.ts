import { IAuthority, NewAuthority } from './authority.model';

export const sampleWithRequiredData: IAuthority = {
  name: '6edc1a4a-7587-4c30-ab47-c0b091984c38',
};

export const sampleWithPartialData: IAuthority = {
  name: 'dabb14d5-9b6d-42c1-a0ce-0a58f802faf1',
};

export const sampleWithFullData: IAuthority = {
  name: 'ba126cd5-e91d-49d2-bd34-ded927a787f8',
};

export const sampleWithNewData: NewAuthority = {
  name: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
