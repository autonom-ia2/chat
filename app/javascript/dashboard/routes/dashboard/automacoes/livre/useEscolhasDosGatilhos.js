import { computed, ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2499 — o que os campos do gatilho de card mostram: os funis e as etapas de
// cada funil (agrupadas pelo funil), das mesmas APIs que o CRM usa. Os nomes
// também servem à frase do gatilho ("Quando o card entra em Orçamento").
const comNome = lista =>
  (lista || []).map(item => ({ value: item.id, label: item.name }));

const porId = lista =>
  Object.fromEntries((lista || []).map(item => [item.id, item.name]));

// O nome do funil de cada etapa, só quando a conta tem mais de um funil: aí a
// frase diz também o funil ("..., no funil Vendas"), porque etapas de funis
// diferentes costumam ter o mesmo nome. Com um funil só, a frase fica curta.
const funilDaEtapa = (funis, etapasPorFunil) => {
  if (funis.length < 2) return {};
  return Object.fromEntries(
    funis.flatMap(funil =>
      (etapasPorFunil[funil.id] || []).map(etapa => [etapa.id, funil.name])
    )
  );
};

export function useEscolhasDosGatilhos() {
  const funis = ref([]);
  const etapasPorFunil = ref({});

  const carregar = async () => {
    const { data } = await CrmKanbanAPI.getPipelines();
    const lista = data.payload || [];
    const respostas = await Promise.all(
      lista.map(funil => CrmKanbanAPI.getStages(funil.id))
    );
    etapasPorFunil.value = Object.fromEntries(
      lista.map((funil, i) => [funil.id, respostas[i].data.payload || []])
    );
    funis.value = lista;
  };

  const escolhas = computed(() => ({
    funis: comNome(funis.value),
    etapas: funis.value.map(funil => ({
      label: funil.name,
      options: comNome(etapasPorFunil.value[funil.id]),
    })),
    // Pela peça do parâmetro (etapa, funil): o id escolhido e o nome dele.
    nomes: {
      funil: porId(funis.value),
      etapa: porId(Object.values(etapasPorFunil.value).flat()),
      funilDaEtapa: funilDaEtapa(funis.value, etapasPorFunil.value),
    },
  }));

  return { escolhas, carregar };
}
