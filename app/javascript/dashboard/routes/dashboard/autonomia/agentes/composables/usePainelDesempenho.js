import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { DESEMPENHO_VIEW_PERMISSION } from 'dashboard/constants/permissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { jornadaAtiva } from './useJornadaAtiva';

// #2226 — o painel de desempenho do agente aparece com a nova jornada de Agentes ligada na conta E a
// flag agentes_painel_desempenho. A rota (guarda) e o link "Ver tudo de {nome}" usam a mesma regra.
export const painelDesempenhoLigado = conta =>
  jornadaAtiva(conta) &&
  conta?.features?.[FEATURE_FLAGS.AGENTES_PAINEL_DESEMPENHO] === true;

// #2251 — o link só aparece para quem pode abrir o painel: administrador ou função com desempenho_view (a rota
// confere a mesma chave em meta.permissions, e a API também).
export function usePainelDesempenho() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  const podeVer = usePermissionGranted(DESEMPENHO_VIEW_PERMISSION);
  // Mesma leitura do useFase2: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      painelDesempenhoLigado(conta.value(contaId.value)) &&
      podeVer.value
  );
}
