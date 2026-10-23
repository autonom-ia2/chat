// #2138 PROTÓTIPO — os itens novos do ⋯ do topo da conversa, só com o painel novo:
// "Mudar time ou prioridade" (ou "Mudar prioridade", sem time na conta) e
// "Acompanhar esta conversa" / "Deixar de acompanhar". O diálogo de time e
// prioridade fica para o PR1b; acompanhar já age, com as ações de hoje.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { painelNovoLigado } from './painelNovo';

export function useItensDoPainelNovo(conversa) {
  const store = useStore();
  const { t } = useI18n();

  const eu = computed(() => store.getters.getCurrentUser);
  const temTime = computed(
    () => (store.getters['teams/getTeams'] || []).length > 0
  );
  const acompanhantes = computed(
    () =>
      store.getters['conversationWatchers/getByConversationId'](
        conversa.value?.id
      ) || []
  );
  const acompanho = computed(() =>
    acompanhantes.value.some(pessoa => pessoa.id === eu.value?.id)
  );

  const itens = computed(() => {
    if (!painelNovoLigado.value) return [];
    return [
      {
        icon: 'i-lucide-users',
        label: temTime.value
          ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.TIME_E_PRIORIDADE')
          : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.SO_PRIORIDADE'),
        action: 'painel_novo_time',
        value: 'painel_novo_time',
      },
      {
        icon: acompanho.value ? 'i-lucide-bell-off' : 'i-lucide-bell',
        label: acompanho.value
          ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.DEIXAR')
          : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ACOMPANHAR'),
        action: 'painel_novo_acompanhar',
        value: 'painel_novo_acompanhar',
      },
    ];
  });

  const alternarAcompanhar = async () => {
    const ids = acompanhantes.value.map(pessoa => pessoa.id);
    const userIds = acompanho.value
      ? ids.filter(id => id !== eu.value.id)
      : [...ids, eu.value.id];
    const deixou = acompanho.value;
    await store.dispatch('conversationWatchers/update', {
      conversationId: conversa.value.id,
      userIds,
    });
    useAlert(
      deixou
        ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.DEIXOU')
        : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ACOMPANHANDO')
    );
  };

  // true quando a ação é daqui (quem chama não faz mais nada).
  const agir = action => {
    if (action === 'painel_novo_time') {
      useAlert(t('PAINEL_DO_CONTATO.MENU_DO_TOPO.AINDA_NAO_FEITO'));
      return true;
    }
    if (action === 'painel_novo_acompanhar') {
      alternarAcompanhar();
      return true;
    }
    return false;
  };

  return { itens, agir };
}
