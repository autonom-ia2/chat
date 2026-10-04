import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  loadCrmAutomationOptions,
  useCrmAutomationOptions,
} from 'dashboard/composables/useCrmAutomationOptions';
import DecisoresAPI from 'dashboard/api/autonomia/decisores';

// #859 — os nomes que a frase da automação usa no lugar dos números: caixas,
// agentes, times e, com o CRM ligado, funis e etapas. Vem da mesma store que o
// modo manual já carrega. Os Decisores (#858) vêm da API deles: a frase do
// passo usa o nome e a descrição da resposta que segue.
const porId = lista =>
  Object.fromEntries((lista || []).map(item => [String(item.id), item.name]));

const decisoresPorId = lista =>
  Object.fromEntries(
    (lista || []).map(({ id, nome, respostas }) => [
      String(id),
      { nome, respostas },
    ])
  );

export function useNomesDaConta() {
  const store = useStore();
  const inboxes = useMapGetter('inboxes/getInboxes');
  const agentes = useMapGetter('agents/getAgents');
  const times = useMapGetter('teams/getTeams');
  const globalConfig = useMapGetter('globalConfig/get');
  const { pipelines, stages } = useCrmAutomationOptions();
  const decisores = ref([]);

  const carregarDecisores = async () => {
    try {
      const { data } = await DecisoresAPI.get();
      decisores.value = data?.decisores || [];
    } catch {
      decisores.value = [];
    }
  };

  // Sem os nomes a frase ainda sai, com "nº 3" (ou "Decisor #12") no lugar do
  // nome — por isso uma falha aqui não impede a tela de abrir.
  const carregarNomes = () => {
    store.dispatch('inboxes/get');
    store.dispatch('agents/get');
    store.dispatch('teams/get');
    carregarDecisores();
    if (globalConfig.value?.crmKanbanEnabled) {
      loadCrmAutomationOptions().catch(() => {});
    }
  };

  const nomes = computed(() => ({
    inboxes: porId(inboxes.value),
    agentes: porId(agentes.value),
    times: porId(times.value),
    funis: porId(pipelines.value),
    etapas: porId(stages.value),
    decisores: decisoresPorId(decisores.value),
  }));

  return { nomes, carregarNomes };
}
