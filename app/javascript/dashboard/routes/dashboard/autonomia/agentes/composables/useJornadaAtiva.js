import { useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #1181 — a nova jornada de Agentes aparece só com o módulo Agentes ligado na conta
// (`autonomia_agents_enabled`, que o guarda da rota já exige) E a flag autonomia_agents_journey.
export const jornadaAtiva = conta =>
  conta?.autonomia_agents_enabled === true &&
  conta?.features?.[FEATURE_FLAGS.AUTONOMIA_AGENTS_JOURNEY] === true;

// Decide UMA vez, no setup de quem chama (DECISOES.md item 1). Não é reativo de propósito: se a conta
// for atualizada na store no meio do uso, a tela não troca de componente (o Construtor antigo faria
// force_close ao ser desmontado). A mudança vale na próxima navegação ou F5.
export function useJornadaAtiva() {
  const { getters } = useStore();
  const conta = getters['accounts/getAccount'](getters.getCurrentAccountId);
  return jornadaAtiva(conta);
}
