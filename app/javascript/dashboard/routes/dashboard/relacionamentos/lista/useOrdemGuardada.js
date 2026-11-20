import { useUISettings } from 'dashboard/composables/useUISettings';
import { ABAS } from '../fonte/grupos';
import { ORDENS } from '../fonte/listaFonte';
import {
  CHAVE_DA_PREFERENCIA,
  CHAVE_DA_PREFERENCIA_DAS_EMPRESAS,
  NA_PREFERENCIA,
  NA_PREFERENCIA_DAS_EMPRESAS,
  ordemNaTabela,
  preferenciaNaTabela,
} from './ordens';

// #3062 — a ordem da aba Pessoas fica guardada para cada pessoa da equipe, na
// mesma preferência que a lista de contatos de hoje usa (lista/ordens.js): ao
// voltar, a lista abre como ela deixou. A demonstração não grava nada.
// #3078 — a aba Empresas também, na preferência da lista de Empresas de hoje
// (`companies_sort_by`): escolher numa tela vale na outra.
const PREFERENCIAS = {
  [ABAS.PESSOAS]: { chave: CHAVE_DA_PREFERENCIA, tabela: NA_PREFERENCIA },
  [ABAS.EMPRESAS]: {
    chave: CHAVE_DA_PREFERENCIA_DAS_EMPRESAS,
    tabela: NA_PREFERENCIA_DAS_EMPRESAS,
  },
};

export const useOrdemGuardada = ({ demo }) => {
  const { uiSettings, updateUISettings } = useUISettings();

  const ordemDaAba = aba => {
    const daAba = PREFERENCIAS[aba];
    if (!daAba) return ORDENS.ULTIMA_CONVERSA;
    return ordemNaTabela(daAba.tabela, uiSettings.value?.[daAba.chave]);
  };

  const guardar = (ordem, aba) => {
    const daAba = PREFERENCIAS[aba];
    if (demo || !daAba) return;
    const guardada = preferenciaNaTabela(daAba.tabela, ordem);
    if (guardada) updateUISettings({ [daAba.chave]: guardada });
  };

  return { ordemDaAba, guardar };
};
