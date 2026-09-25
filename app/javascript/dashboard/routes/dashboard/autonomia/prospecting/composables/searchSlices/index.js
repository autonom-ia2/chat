// Pedaços da tela de busca, um por frente. Cada pedaço é dono do próprio
// estado e diz, no próprio arquivo:
//   formDefaults(settings) chaves do formulário de nova busca e seus valores
//   createState()          refs que só ele usa
//   reset(state)           o que "Nova busca" limpa
//   restore(state, search) o que volta ao reabrir uma busca salva
//   restoreForm(state, search) o que volta ao formulário para repetir ou
//                          editar uma busca salva (#678)
//   toPayload(state)       { body, metadata } do pedido de criar a busca
// Todos os campos são opcionais. Os pedaços são juntados com mergeDisjoint:
// dois pedaços com a mesma chave quebram a montagem, em vez de um sobrescrever
// o outro. A ordem da lista é a ordem das chaves no pedido.
import { mergeDisjoint } from '../../utils/mergeDisjoint';
import { baseSlice } from './baseSlice';
import { filtersSlice } from './filtersSlice';
import { locationSlice } from './locationSlice';
import { modeSlice } from './modeSlice';

export const SEARCH_SLICES = [
  baseSlice,
  locationSlice,
  filtersSlice,
  modeSlice,
];

export const sliceFormDefaults = settings =>
  mergeDisjoint(
    ...SEARCH_SLICES.map(slice => slice.formDefaults?.(settings) || {})
  );

export const createSliceState = () =>
  mergeDisjoint(...SEARCH_SLICES.map(slice => slice.createState?.() || {}));

export const resetSlices = state => {
  SEARCH_SLICES.forEach(slice => slice.reset?.(state));
};

export const restoreSlices = (state, search) => {
  SEARCH_SLICES.forEach(slice => slice.restore?.(state, search));
};

export const restoreFormSlices = (state, search) => {
  SEARCH_SLICES.forEach(slice => slice.restoreForm?.(state, search));
};

export const buildSearchRequest = state => {
  const parts = SEARCH_SLICES.map(slice => slice.toPayload?.(state) || {});
  const metadata = mergeDisjoint(...parts.map(part => part.metadata || {}));
  return mergeDisjoint(...parts.map(part => part.body || {}), { metadata });
};
