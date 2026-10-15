import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  PAPEL_AJUDANTE_NA_QUERY,
  caixasNaQuery,
  papelDaQuery,
  principaisDaQuery,
  quandoDaQuery,
} from '../constants/criacao';
import { principaisPossiveis } from '../utils/ajudante';
import { useAjudaDoAgente } from './useAjudaDoAgente';

// Tema 14 (#1434) — "Ajuda outros agentes" na criação, como o agente da equipe (#1433): ANTES da conversa,
// em página inteira, "Quem {nome} vai ajudar?" e "Quando chamar {nome}?". A escolha vai para a URL
// (`?ajuda=3,4&quando=…`, junto de `?papel=ajudante` e depois de `?agente=`): F5 não pergunta de novo.
// Depois, a conversa abre com `papel: 'ajudante'` (o agente nasce interno e com a marca de origem). No
// Confira, "Começar a ajudar" grava o vínculo (PUT /ajuda) e liga o agente, sem canal: ele é interno.
// - Criar um ajudante novo pede a Fase 2. Um rascunho que JÁ nasceu ajudante (`ajudante` do servidor, a marca)
//   continua ajudante mesmo sem ela: nunca é ligado como Copiloto. Sem a Fase 2, o vínculo não grava, então
//   "Começar" fica bloqueado com o motivo (`bloqueado`).
// - Rascunho continuado pela lista (só `?agente=`) volta aos passos se ainda não escolheu quem ajuda.
// - "Começar" relê os agentes e manda só os escolhidos que ainda podem ser ajudados; sem nenhum, volta aos
//   passos.
// `agente`/`nome`: o rascunho; `fase2`: a chave da conta; `conversa`: a conversa de criação; `idInicial`: o
// rascunho da URL; `voltarParaLista`: a saída da criação (pergunta antes, se há rascunho); `aoComecar`: recebe
// quem ele ajuda depois de ligar (abre o Pronto).
export function useAjudanteNaCriacao({
  agente,
  nome,
  fase2,
  conversa,
  idInicial,
  voltarParaLista,
  aoComecar,
}) {
  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const registros = useMapGetter('autonomiaAgents/getRecords');
  const ajuda = useAjudaDoAgente();

  const pedidoNaQuery = () =>
    papelDaQuery(route.query) === PAPEL_AJUDANTE_NA_QUERY;
  const ajudante = computed(
    () => agente.value?.ajudante === true || (fase2.value && pedidoNaQuery())
  );
  const bloqueado = computed(() => ajudante.value && !fase2.value);
  const principaisNaQuery = computed(() => principaisDaQuery(route.query));
  const quandoNaQuery = computed(() => quandoDaQuery(route.query));
  const escolheu = () =>
    principaisNaQuery.value.length > 0 && Boolean(quandoNaQuery.value);

  // Os passos do começo: ajudante que pode gravar e ainda não escolheu quem ajuda (ou pediu "Alterar").
  const podeEscolher = computed(() => ajudante.value && !bloqueado.value);
  const escolhendo = ref(podeEscolher.value && !escolheu());
  // A conta (e a Fase 2) pode chegar à store depois de a página montar; o rascunho continuado também.
  watch(podeEscolher, pode => {
    if (pode && !escolheu()) escolhendo.value = true;
  });

  // Os agentes da conta: para escolher quem ele ajuda, para os nomes do resumo e para conferir, ao começar,
  // quem ainda pode ser ajudado. No F5 (ou no rascunho continuado) a store só tem o próprio rascunho.
  const leitura = ref('pronto');
  let lendo = null;
  const carregarAgentes = () => {
    if (!lendo) {
      leitura.value = 'carregando';
      lendo = store
        .dispatch('autonomiaAgents/get')
        .then(() => {
          leitura.value = 'pronto';
        })
        .catch(() => {
          leitura.value = 'erro';
        })
        .finally(() => {
          lendo = null;
        });
    }
    return lendo;
  };
  watch(escolhendo, aberto => {
    if (aberto) carregarAgentes();
  });
  watch(
    ajudante,
    ligado => {
      if (ligado) carregarAgentes();
    },
    { immediate: true }
  );

  const agentes = computed(() => registros.value || []);
  // Os escolhidos que ainda podem ser ajudados (falam com cliente, terminados, não são a Cotação).
  const validos = computed(() => {
    const livres = principaisPossiveis(agentes.value, agente.value?.id ?? null)
      .filter(item => !item.bloqueio)
      .map(item => item.agente.id);
    return principaisNaQuery.value.filter(id => livres.includes(id));
  });
  const principais = computed(() =>
    validos.value
      .map(id => agentes.value.find(item => item.id === id))
      .map(item => ({ id: item.id, name: item.name }))
  );
  const inicial = computed(() => ({
    principais: principaisNaQuery.value,
    quando: quandoNaQuery.value,
  }));

  const alterar = () => {
    escolhendo.value = true;
  };

  // Escolheu (passo 2): vai para a URL, com a marca do papel (o rascunho continuado pode não tê-la), e a
  // conversa começa na primeira vez.
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
    if (
      !idInicial &&
      !conversa.agenteId.value &&
      !conversa.falas.value.length
    ) {
      conversa.comecar();
    }
  };

  // Voltar do primeiro passo: com a escolha já feita, volta à criação; com rascunho, sai (perguntando);
  // sem nada, volta à página "Criar agente".
  const voltar = () => {
    if (escolheu()) {
      escolhendo.value = false;
      return;
    }
    if (conversa.agenteId.value) {
      voltarParaLista();
      return;
    }
    router.replace({ query: {} });
  };

  // "Começar a ajudar": grava quem ele ajuda e liga o agente. Nunca liga um ajudante sem vínculo: sem
  // escolha (ou sem nenhum escolhido ainda válido), volta aos passos. O PUT vem antes de ligar: recusado,
  // a explicação do servidor aparece no topo e o agente segue parado.
  const comecando = ref(false);
  const naoLeu = () => {
    ajuda.erro.value = {
      titulo: t('AGENTS.JORNADA.AJUDANTE.QUEM.ERRO_LER'),
      garantia: t('AGENTS.JORNADA.AJUDANTE.ERRO_GARANTIA', {
        nome: nome.value,
      }),
    };
  };
  const gravarELigar = async id => {
    const lista = principais.value;
    const gravou = await ajuda.salvar({
      agenteId: id,
      nome: nome.value,
      principalIds: validos.value,
      quando: quandoNaQuery.value,
    });
    if (!gravou) return;
    await store.dispatch('autonomiaAgents/update', {
      id,
      enabled: true,
      status: 'active',
    });
    aoComecar(lista);
  };
  const comecar = async () => {
    if (comecando.value || bloqueado.value) return;
    if (!escolheu()) {
      alterar();
      return;
    }
    comecando.value = true;
    ajuda.erro.value = null;
    try {
      await carregarAgentes();
      if (leitura.value === 'erro') {
        naoLeu();
        return;
      }
      if (!validos.value.length) {
        alterar();
        return;
      }
      await gravarELigar(agente.value.id);
    } catch {
      useAlert(
        t('AGENTS.JORNADA.CRIAR.COMECE.ERRO_INTERNO', { nome: nome.value })
      );
    } finally {
      comecando.value = false;
    }
  };

  return {
    ajudante,
    bloqueado,
    escolhendo,
    leitura,
    agentes,
    principais,
    inicial,
    quando: quandoNaQuery,
    salvando: ajuda.salvando,
    comecando,
    erro: ajuda.erro,
    carregarAgentes,
    escolher,
    voltar,
    alterar,
    comecar,
    sair: voltarParaLista,
  };
}
