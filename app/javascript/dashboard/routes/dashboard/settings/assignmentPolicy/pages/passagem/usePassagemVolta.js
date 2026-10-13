import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';

// #1385 — para onde a passagem volta. A seta, o X e o "Fechar" de cada tela vão para o mesmo lugar: de onde a pessoa
// veio. Quem abriu um funil pelo Kanban (menu Configurar, `?from=crm`) volta ao Kanban, no mesmo funil
// (`?pipeline_id=`); quem veio da lista volta à lista. A lista volta a "Atribuição de agentes", onde o administrador
// a encontra no menu; quem não chega lá (função personalizada, ou conta sem Atribuição) volta ao Kanban.
export const ORIGEM_KANBAN = 'crm';

const kanban = pipelineId => ({
  name: 'crm_kanban_index',
  ...(pipelineId ? { query: { pipeline_id: String(pipelineId) } } : {}),
});

export function usePassagemVolta() {
  const route = useRoute();
  const { t } = useI18n();
  const { isAdmin } = useAdmin();
  const temRecurso = useMapGetter('accounts/isFeatureEnabledonAccount');

  // A volta da tela de um funil.
  const doFunil = computed(() => {
    if (route.query.from === ORIGEM_KANBAN) {
      return {
        rotulo: t('CRM_KANBAN.PASSAGEM.HEROI.VOLTAR_KANBAN'),
        destino: kanban(route.params.pipelineId),
      };
    }
    return {
      rotulo: t('CRM_KANBAN.PASSAGEM.HEROI.TODOS_OS_FUNIS'),
      destino: { name: 'crm_handoff_settings_index' },
    };
  });

  // A volta da lista de funis.
  const daLista = computed(() => {
    const contaId = Number(route.params.accountId);
    if (isAdmin.value && temRecurso.value(contaId, 'assignment_v2')) {
      return {
        rotulo: t('ASSIGNMENT_POLICY.INDEX.HEADER.TITLE'),
        destino: { name: 'assignment_policy_index' },
      };
    }
    return {
      rotulo: t('CRM_KANBAN.PASSAGEM.HEROI.VOLTAR_KANBAN'),
      destino: kanban(),
    };
  });

  return { doFunil, daLista };
}
