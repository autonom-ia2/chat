import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import AttributeAPI from 'dashboard/api/attributes';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { semAtributosInternosDoWhatsapp } from 'dashboard/helper/atributosInternosDoWhatsapp';

// #2499 — o que os campos do gatilho de card mostram: os funis e as etapas de
// cada funil (agrupadas pelo funil), das mesmas APIs que o CRM usa. Os nomes
// também servem à frase do gatilho ("Quando o card entra em Orçamento"), e o
// da caixa da conversa nova (#2680) vem da lista de caixas que a tela carrega.
const comNome = (lista, nome = 'name') =>
  (lista || []).map(item => ({ value: item.id, label: item[nome] }));

const porId = (lista, nome = 'name') =>
  Object.fromEntries((lista || []).map(item => [item.id, item[nome]]));

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

// Os gatilhos de data (#2499 PR3a) escolhem um campo personalizado do tipo data
// do próprio alvo: o do card para o card, o do contato para o contato.
const MODELO_DO_ALVO = {
  'Crm::Card': 'card_attribute',
  Contact: 'contact_attribute',
};
const camposDeData = (definicoes, modelo) =>
  definicoes
    .filter(
      item =>
        item.attribute_model === modelo &&
        item.attribute_display_type === 'date'
    )
    .map(item => ({
      value: item.attribute_key,
      label: item.attribute_display_name,
    }));
const porAlvo = (definicoes, montar) =>
  Object.fromEntries(
    Object.entries(MODELO_DO_ALVO).map(([alvo, modelo]) => [
      alvo,
      montar(camposDeData(definicoes, modelo)),
    ])
  );

// G27 (#2661): o "card atualizado" escolhe qualquer campo personalizado do
// card, de qualquer tipo.
const camposDoCard = definicoes =>
  definicoes
    .filter(item => item.attribute_model === 'card_attribute')
    .map(item => ({
      value: item.attribute_key,
      label: item.attribute_display_name,
    }));

// As peças que pedem os funis e as etapas; "campo" pede os campos de data e
// "mudanca", os campos do card.
const PECAS_DO_FUNIL = ['etapa', 'funil'];
const PECAS_DOS_CAMPOS = ['campo', 'mudanca'];

export function useEscolhasDosGatilhos() {
  const funis = ref([]);
  const etapasPorFunil = ref({});
  const definicoes = ref([]);
  // G32: as páginas de agendamento, para o filtro dos gatilhos de reunião.
  const paginas = ref([]);
  const caixas = useMapGetter('inboxes/getInboxes');

  const carregarFunis = async () => {
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

  const carregarCampos = async () => {
    const { data } = await AttributeAPI.getAttributesByModel();
    definicoes.value = semAtributosInternosDoWhatsapp(data || []);
  };

  const carregarPaginas = async () => {
    const { data } = await CrmBookingPagesAPI.get();
    paginas.value = data.payload || [];
  };

  // Só o que as peças pedem. Sem peças, os funis (como sempre foi).
  const carregar = async (pecas = PECAS_DO_FUNIL) => {
    const leituras = [];
    if (pecas.some(peca => PECAS_DO_FUNIL.includes(peca)))
      leituras.push(carregarFunis());
    if (pecas.some(peca => PECAS_DOS_CAMPOS.includes(peca)))
      leituras.push(carregarCampos());
    if (pecas.includes('pagina')) leituras.push(carregarPaginas());
    await Promise.all(leituras);
  };

  const escolhas = computed(() => ({
    funis: comNome(funis.value),
    paginas: comNome(paginas.value, 'title'),
    etapas: funis.value.map(funil => ({
      label: funil.name,
      options: comNome(etapasPorFunil.value[funil.id]),
    })),
    // Os campos de data, pelo alvo do gatilho: { 'Crm::Card': [...], Contact }.
    campos: porAlvo(definicoes.value, lista => lista),
    camposDoCard: camposDoCard(definicoes.value),
    // Pela peça do parâmetro (etapa, funil): o id escolhido e o nome dele. O
    // campo vai também pelo alvo, porque card e contato podem ter a mesma chave.
    nomes: {
      campo: porAlvo(definicoes.value, lista =>
        Object.fromEntries(lista.map(item => [item.value, item.label]))
      ),
      campoDoCard: Object.fromEntries(
        camposDoCard(definicoes.value).map(item => [item.value, item.label])
      ),
      funil: porId(funis.value),
      pagina: porId(paginas.value, 'title'),
      etapa: porId(Object.values(etapasPorFunil.value).flat()),
      funilDaEtapa: funilDaEtapa(funis.value, etapasPorFunil.value),
      caixa: porId(caixas.value),
    },
  }));

  return { escolhas, carregar };
}
