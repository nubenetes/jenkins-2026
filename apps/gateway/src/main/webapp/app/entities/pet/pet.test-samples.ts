import dayjs from 'dayjs/esm';

import { IPet, NewPet } from './pet.model';

export const sampleWithRequiredData: IPet = {
  id: 17427,
  name: 'whoa because righteously',
};

export const sampleWithPartialData: IPet = {
  id: 24239,
  name: 'between',
};

export const sampleWithFullData: IPet = {
  id: 29849,
  name: 'expense gah huzzah',
  birthDate: dayjs('2026-06-15'),
};

export const sampleWithNewData: NewPet = {
  name: 'earnest refine',
  id: null,
};

Object.freeze(sampleWithNewData);
Object.freeze(sampleWithRequiredData);
Object.freeze(sampleWithPartialData);
Object.freeze(sampleWithFullData);
