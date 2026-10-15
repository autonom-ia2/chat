import { computed, ref, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { accountTimeZone } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import TeamsAPI from 'dashboard/api/teams';

// #1460/#1462 — o que as telas de lembrete precisam saber da conta: o fuso
// (o de Configurações, nunca o do navegador), quem é você, a equipe, quem não
// vê o funil do card (owner_options) e quem está em cada time. Tudo real:
// nada disso precisa do adaptador falso.
// Só carrega com a flag ligada (`ligado`): desligada, nada sai para a API.
export const useLembreteContexto = ({ store, card, agentes, ligado }) => {
  const { currentAccount } = useAccount();
  const fuso = computed(() => accountTimeZone(currentAccount.value));
  const fusoRotulo = computed(() => rotuloDoFuso(fuso.value));

  const eu = computed(() => {
    const usuario = store.getters.getCurrentUser || {};
    return { id: usuario.id, name: usuario.name || usuario.display_name };
  });
  const dono = computed(() => {
    const owner = card.value?.owner;
    return owner?.id ? { id: owner.id, name: owner.name } : null;
  });
  const listaDeAgentes = computed(
    () => agentes?.value || store.getters['agents/getAgents'] || []
  );

  const barrados = ref([]);
  const carregarBarrados = async () => {
    barrados.value = [];
    if (!ligado.value || !card.value?.id) return;
    try {
      const { data } = await CrmKanbanAPI.getOwnerOptions({
        cardIds: [card.value.id],
      });
      barrados.value = data?.payload?.cards?.[card.value.id] || [];
    } catch {
      // Sem a lista, o servidor ainda recusa quem não vê o funil.
    }
  };
  watch(() => [card.value?.id, ligado.value], carregarBarrados, {
    immediate: true,
  });

  const times = computed(() => store.getters['teams/getTeams'] || []);
  const membros = ref({});
  const carregarTimes = async () => {
    try {
      await store.dispatch('teams/get');
      const pares = await Promise.all(
        times.value.map(async time => {
          const { data } = await TeamsAPI.getAgents({ teamId: time.id });
          return [time.id, (data || []).map(pessoa => pessoa.name)];
        })
      );
      membros.value = Object.fromEntries(pares);
    } catch {
      membros.value = {};
    }
  };
  watch(
    ligado,
    sim => {
      if (sim) carregarTimes();
    },
    { immediate: true }
  );

  return {
    fuso,
    fusoRotulo,
    eu,
    dono,
    agentes: listaDeAgentes,
    barrados,
    times,
    membros,
  };
};
