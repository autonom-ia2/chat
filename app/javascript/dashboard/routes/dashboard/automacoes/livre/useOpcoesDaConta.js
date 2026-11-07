import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';

// #2414 F5 — as escolhas da conta que os campos do "Alterar" mostram: pessoas,
// times, caixas, etiquetas e campos personalizados. Vêm das mesmas stores que o
// resto do painel usa. A etiqueta vai pelo nome (é assim que a conversa e o
// contato a guardam); pessoa, time, caixa e o alvo de "Mudar" vão pelo id.
const MODELO_DA_PECA = {
  atributos_da_conversa: 'conversation_attribute',
  atributos_do_contato: 'contact_attribute',
  atributos_da_empresa: 'company_attribute',
};
export const modeloDaPeca = peca => MODELO_DA_PECA[peca] || null;

const comNome = (lista, rotulo = 'name') =>
  (lista || []).map(item => ({ value: item.id, label: item[rotulo] }));

export function useOpcoesDaConta() {
  const store = useStore();
  const agentes = useMapGetter('agents/getAgents');
  const times = useMapGetter('teams/getTeams');
  const caixas = useMapGetter('inboxes/getInboxes');
  const etiquetas = useMapGetter('labels/getLabels');
  const atributosDo = useMapGetter('attributes/getAttributesByModel');
  // G15: as agentes de IA vêm da própria Automação (só id e nome), não da
  // tela de Agentes, que pede outra permissão. `null` enquanto carrega; se a
  // lista não vem, o painel diz que não carregou (nunca "a conta não tem").
  const agentesDeIa = ref(null);
  const agentesDeIaFalhou = ref(false);
  const carregarAgentesDeIa = async () => {
    agentesDeIaFalhou.value = false;
    try {
      const { data } = await AutomacoesAPI.agentesDeIa();
      agentesDeIa.value = data.agentes || [];
    } catch {
      agentesDeIaFalhou.value = true;
    }
  };

  const carregarOpcoes = () => {
    [
      'agents/get',
      'teams/get',
      'inboxes/get',
      'labels/get',
      'attributes/get',
    ].forEach(acao => store.dispatch(acao));
    carregarAgentesDeIa();
  };

  const opcoes = computed(() => ({
    pessoa: comNome(agentes.value),
    time: comNome(times.value),
    caixa: comNome(caixas.value),
    agenteDeIa: agentesDeIa.value && comNome(agentesDeIa.value),
    agenteDeIaFalhou: agentesDeIaFalhou.value,
    // G2: só as caixas de e-mail, por onde o passo "email" sai.
    caixaDeEmail: comNome(
      (caixas.value || []).filter(
        caixa => caixa.channel_type === 'Channel::Email'
      )
    ),
    etiquetaPorNome: (etiquetas.value || []).map(item => ({
      value: item.title,
      label: item.title,
    })),
    etiqueta: comNome(etiquetas.value, 'title'),
    // G7: o campo do contato na seleção do recorrente vai pela chave.
    atributoDoContato: (atributosDo.value('contact_attribute') || []).map(
      item => ({
        value: item.attribute_key,
        label: item.attribute_display_name,
      })
    ),
    atributo: [
      'conversation_attribute',
      'contact_attribute',
      'company_attribute',
    ].flatMap(modelo =>
      comNome(atributosDo.value(modelo), 'attribute_display_name')
    ),
  }));

  const atributosDoModelo = modelo => atributosDo.value(modelo) || [];
  const atributosDaPeca = peca => atributosDoModelo(modeloDaPeca(peca));

  return {
    opcoes,
    atributosDaPeca,
    atributosDo: atributosDoModelo,
    carregarOpcoes,
  };
}
