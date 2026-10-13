import { useStore } from 'dashboard/composables/store';

// #1424 — o protótipo da Fase 2 aparece só na conta em que o servidor diz que ele está ligado
// (ENV AUTONOMIA_FASE2_PROTOTIPO, instalação de desenvolvimento). Decide uma vez, no setup.
export function usePrototipoFase2() {
  // Store sem o módulo de contas (specs das telas) = protótipo desligado.
  const getters = useStore()?.getters;
  const conta = getters?.['accounts/getAccount']?.(getters.getCurrentAccountId);
  return conta?.autonomia_fase2_prototipo === true;
}
