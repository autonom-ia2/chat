import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #2473: espelho de Autonomia::Automacao::RegraDoFunil. Com a flag da fundação, a regra que cria, move, ganha, perde ou
// atribui card, ou que depende do funil nas condições, pede também a chave de funis (crm_manage_pipelines ou crm_admin;
// admin sempre). Mexer numa regra que tem (ou vai ter) uma delas é o que o servidor confere; a tela avisa antes do 403.
export const ACOES_DO_FUNIL = [
  'crm_create_card',
  'crm_move_card_stage',
  'crm_mark_card_won',
  'crm_mark_card_lost',
  'crm_assign_card_owner',
];
export const CONDICOES_DO_FUNIL = [
  'crm_pipeline_id',
  'crm_stage_id',
  'crm_card_status',
];

const usaAlguma = (lista, campo, chaves) =>
  (lista || []).some(item => chaves.includes(item[campo]));

export const mexeNoFunil = ({ actions, conditions }) =>
  usaAlguma(actions, 'action_name', ACOES_DO_FUNIL) ||
  usaAlguma(conditions, 'attribute_key', CONDICOES_DO_FUNIL);

export function useRegraDoFunil() {
  const { isCloudFeatureEnabled } = useAccount();
  const gerenciaFunis = usePermissionGranted('crm_manage_pipelines');
  const administraCrm = usePermissionGranted('crm_admin');
  const podeFunil = computed(
    () =>
      !isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_FUNDACAO) ||
      gerenciaFunis.value ||
      administraCrm.value
  );
  // Cada regra é { actions, conditions }: a de agora e a com que a tela abriu (tirar o passo de funil também é mexer).
  const travadaNoFunil = (...regras) =>
    !podeFunil.value && regras.some(regra => mexeNoFunil(regra || {}));

  return { podeFunil, travadaNoFunil };
}
