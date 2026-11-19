import { useUISettings } from 'dashboard/composables/useUISettings';
import { ABAS } from '../fonte/grupos';
import { ORDENS } from '../fonte/listaFonte';
import {
  CHAVE_DA_PREFERENCIA,
  ordemDaPreferencia,
  preferenciaDaOrdem,
} from './ordens';

// #3062 — a ordem da aba Pessoas fica guardada para cada pessoa da equipe, na
// mesma preferência que a lista de contatos de hoje usa (lista/ordens.js): ao
// voltar, a lista abre como ela deixou. A aba Empresas abre sempre pela última
// conversa. A demonstração não grava nada.
export const useOrdemGuardada = ({ demo }) => {
  const { uiSettings, updateUISettings } = useUISettings();

  const ordemDaAba = aba =>
    aba === ABAS.PESSOAS
      ? ordemDaPreferencia(uiSettings.value?.[CHAVE_DA_PREFERENCIA])
      : ORDENS.ULTIMA_CONVERSA;

  const guardar = (ordem, aba) => {
    if (demo || aba !== ABAS.PESSOAS) return;
    const guardada = preferenciaDaOrdem(ordem);
    if (guardada) updateUISettings({ [CHAVE_DA_PREFERENCIA]: guardada });
  };

  return { ordemDaAba, guardar };
};
