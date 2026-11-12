import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

// #2499 F6.3/F6.5 — quem vê as automações do motor novo no card e na etapa.

// As partes vêm com o motor e os gatilhos de card, como o resto da F6 (Motor.gatilhos? no servidor; o CRM ligado é o
// próprio funil aberto).
const FLAGS = ['automacao_fundacao', 'automacao_motor', 'automacao_gatilhos'];
export const useAutomacaoNoCrmLigada = () => {
  const { isCloudFeatureEnabled } = useAccount();
  return computed(() => FLAGS.every(flag => isCloudFeatureEnabled(flag)));
};

// Ver as automações pede `automation_view` (quem tem `automation_manage` também vê); o administrador sempre vê.
export const usePodeVerAutomacoes = () => {
  const ligada = useAutomacaoNoCrmLigada();
  const ver = usePermissionGranted('automation_view');
  const mudar = usePermissionGranted('automation_manage');
  return computed(() => ligada.value && (ver.value || mudar.value));
};

// Erro de permissão não é falha passageira: some o painel, sem "Tentar de novo".
export const semPermissao = erro => [401, 403].includes(erro?.response?.status);
