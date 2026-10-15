import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import {
  PAPEL_AJUDANTE_NA_QUERY,
  caixasNaQuery,
  papelDaQuery,
  principaisDaQuery,
  quandoDaQuery,
} from '../constants/criacao';
import { useAjudaDoAgente } from './useAjudaDoAgente';

// Tema 14 (#1434) — "Ajuda outros agentes" na criação, como o agente da equipe (#1433): ANTES da conversa,
// em página inteira, "Quem {nome} vai ajudar?" e "Quando chamar {nome}?". A escolha vai para a URL
// (`?ajuda=3,4&quando=…`, junto de `?papel=ajudante` e depois de `?agente=`): F5 não pergunta de novo.
// Depois, a conversa abre com `papel: 'ajudante'` (o agente nasce interno e com a marca de origem). No
// Confira, "Começar a ajudar" grava o vínculo (PUT /ajuda) e liga o agente, sem canal: ele é interno.
// Só com a Fase 2. Rascunho de ajudante continuado pela lista (só `?agente=`) é reconhecido pela marca
// (`ajudante` do servidor) e volta aos passos se ainda não escolheu quem ajuda.
// `agente`: o rascunho (computed); `fase2`: a chave da conta (computed).
export function useAjudanteNaCriacao({ agente, fase2 }) {
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const registros = useMapGetter('autonomiaAgents/getRecords');
  const ajuda = useAjudaDoAgente();

  const pedidoNaQuery = () =>
    papelDaQuery(route.query) === PAPEL_AJUDANTE_NA_QUERY;
  const ajudante = computed(
    () => fase2.value && (pedidoNaQuery() || agente.value?.ajudante === true)
  );
  const principaisNaQuery = computed(() => principaisDaQuery(route.query));
  const quandoNaQuery = computed(() => quandoDaQuery(route.query));
  const escolheu = () =>
    principaisNaQuery.value.length > 0 && Boolean(quandoNaQuery.value);

  // Os passos do começo: ajudante que ainda não escolheu quem ajuda (ou pediu "Alterar").
  const escolhendo = ref(ajudante.value && !escolheu());
  // A conta (e a Fase 2) pode chegar à store depois de a página montar; o rascunho continuado também.
  watch(ajudante, ligado => {
    if (ligado && !escolheu()) escolhendo.value = true;
  });

  // Os agentes da conta, para escolher quem ele ajuda. Lidos sempre que os passos abrem: no F5 (ou no
  // rascunho continuado) a store só tem o próprio rascunho.
  const leitura = ref('pronto');
  const carregarAgentes = async () => {
    if (leitura.value === 'carregando') return;
    leitura.value = 'carregando';
    try {
      await store.dispatch('autonomiaAgents/get');
      leitura.value = 'pronto';
    } catch {
      leitura.value = 'erro';
    }
  };
  watch(escolhendo, aberto => {
    if (aberto) carregarAgentes();
  });
  // Também fora dos passos: o resumo do topo e o Pronto mostram os nomes de quem ele ajuda.
  watch(
    ajudante,
    ligado => {
      if (ligado) carregarAgentes();
    },
    { immediate: true }
  );

  const agentes = computed(() => registros.value || []);
  // Os escolhidos, com o nome da lista da conta (id sem agente na lista não aparece).
  const principais = computed(() =>
    principaisNaQuery.value
      .map(id => agentes.value.find(item => item.id === id))
      .filter(Boolean)
      .map(item => ({ id: item.id, name: item.name }))
  );
  const inicial = computed(() => ({
    principais: principaisNaQuery.value,
    quando: quandoNaQuery.value,
  }));

  // Escolheu (passo 2): vai para a URL, com a marca do papel (o rascunho continuado pode não tê-la).
  const escolher = ({ principais: ids, quando }) => {
    ajuda.erro.value = null;
    router.replace({
      query: {
        ...route.query,
        papel: PAPEL_AJUDANTE_NA_QUERY,
        ajuda: caixasNaQuery(ids),
        quando,
      },
    });
    escolhendo.value = false;
  };

  const alterar = () => {
    escolhendo.value = true;
  };

  // "Começar a ajudar": grava quem ele ajuda e liga o agente. Sem escolha, volta aos passos: nunca liga
  // um ajudante sem vínculo. O PUT vem antes de ligar: recusado, nada mudou e o agente segue parado.
  const comecar = async ({ id, nome }) => {
    if (!escolheu()) {
      alterar();
      return false;
    }
    const gravou = await ajuda.salvar({
      agenteId: id,
      nome,
      principalIds: principaisNaQuery.value,
      quando: quandoNaQuery.value,
    });
    if (!gravou) return false;
    await store.dispatch('autonomiaAgents/update', {
      id,
      enabled: true,
      status: 'active',
    });
    return true;
  };

  return {
    ajudante,
    escolhendo,
    leitura,
    agentes,
    principais,
    inicial,
    quando: quandoNaQuery,
    salvando: ajuda.salvando,
    erro: ajuda.erro,
    carregarAgentes,
    escolher,
    alterar,
    comecar,
  };
}
