<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useEventListener, useMediaQuery } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import { useConversaDeCriacao } from '../composables/useConversaDeCriacao';
import { useTesteDoAgente } from '../composables/useTesteDoAgente';
import { useCanaisOcupados } from '../composables/useCanaisOcupados';
import { useComecarAAtender } from '../composables/useComecarAAtender';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';
import { useFase2 } from '../composables/useFase2';
import { useSalvarEquipe } from '../composables/useSalvarEquipe';
import {
  ATUACAO,
  ETAPA,
  IDEIAS_PARA_COMECAR,
  PAPEL_AREA_NA_QUERY,
  atuacaoDaQuery,
  etapaDaQuery,
  exemploDoModelo,
  idDaQuery,
  modeloDaQuery,
  modeloDoTipo,
  papelDaQuery,
  perguntasDeTeste,
} from '../constants/criacao';
import { MODELO_DO_MEU_JEITO, MODELOS } from '../constants/modelos';
import {
  TRABALHANDO,
  canaisDoAgente,
  estadoDeAtendimento,
} from '../utils/estadoDoAgente';
import { caixasDaEquipe } from '../utils/ondeTrabalha';
import { fecharFrase } from '../utils/pagina';
import {
  canalSugerido,
  horariosDasCaixas,
  tipoDoCanalParaTexto,
} from '../utils/criacao';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteConfirmacao from '../components/AgenteConfirmacao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import AgentesEtapas from '../components/AgentesEtapas.vue';
import CelularConversa from '../components/CelularConversa.vue';
import EtapaConte from '../components/criar/EtapaConte.vue';
import EtapaConfira from '../components/criar/EtapaConfira.vue';
import EtapaComece from '../components/criar/EtapaComece.vue';
import EtapaPronto from '../components/criar/EtapaPronto.vue';
import BaseDaCriacao from '../components/criar/BaseDaCriacao.vue';
import EquipeCanais from '../components/onde/EquipeCanais.vue';
import ResumoOndeTrabalha from '../components/onde/ResumoOndeTrabalha.vue';

// #1181 PR2 — criar agente: Conte · Confira · Comece · Pronto (protótipo T03–T06), atrás da flag
// autonomia_agents_journey (o seletor da rota decide). A etapa vem da query (`?etapa=`), e só vale
// quando já dá para estar nela: sem a conversa fechada fica em Conte; Pronto só com o agente
// atendendo. #1504 — o teste é opcional: Comece só exige a conversa fechada (e um canal).
// - Computador: uma tela só. A conversa fica à esquerda e o celular à direita, que vira teste
//   quando a conversa fecha. Comece é a folha à direita.
// - Celular: uma etapa por tela, sem troca automática. Quando a conversa fecha, a barra embaixo
//   vira "Ver como {nome} responde". O CTA fica fixo embaixo, com 56 px.
// Modelo novo: a conversa abre ao montar (a IA fala primeiro). Assim que o rascunho existe, a query
// troca `?modelo=` por `?agente=`: F5 continua o mesmo rascunho em vez de criar outro (o modelo,
// daí em diante, vem do agent_type do rascunho).
// #1494 — Copiloto da equipe (`?atuacao=interno`): a conversa abre com actuation internal. Sem
// exemplo de cliente nem ideias de loja; o teste usa perguntas da equipe e o Comece só liga o agente,
// sem canal. Antes do rascunho existir, a atuação vem da query; depois, do próprio agente.
// #1503 — "Base de conhecimento de {nome}" só no Conte: no computador, na coluna da direita abaixo do
// exemplo; no celular, um botão "Base" ao lado de "Ver exemplo" abre a mesma caixa numa gaveta. A
// lista é a do clipe da conversa (conversa.base). Vale para o agente externo e para o copiloto.
// #1504 — "Fazer ajustes avançados" (no Confira) deixa o agente parado (status paused), sem ligar
// caixa nenhuma, e abre a página dele; vale para os dois tipos. Terminar depois é o "Voltar" do topo.
// #1543 — vinda da página "Criar agente" (mesma rota, a criação toma o lugar dela): o foco vai ao
// título da criação, para teclado e leitor de tela saberem que a tela mudou.
// #1433 (tema 13) — agente da equipe (`?papel=area`, só com a Fase 2): a conversa é a de sempre; o
// Comece escolhe os canais que já têm principal atendendo (os outros, bloqueados com o motivo), passa
// pelo "Confira como fica" e grava o vínculo de área, que já liga o agente. A marca fica na query
// junto de `?agente=` (F5). Pronto mostra "Onde {nome} trabalha" (caixa e papel).
const props = defineProps({
  focarTitulo: { type: Boolean, default: false },
});

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const celular = useMediaQuery('(max-width: 767px)');

const modeloPedido = modeloDaQuery(route.query);
const idInicial = idDaQuery(route.query);
const atuacaoPedida = atuacaoDaQuery(route.query);

const conversa = useConversaDeCriacao({
  modelo: modeloPedido,
  atuacao: atuacaoPedida,
});
// O rascunho ainda está sendo escrito pelo Construtor: só o id; quem diz "incompleto" é o 422.
const teste = useTesteDoAgente(
  computed(() => ({ id: conversa.agenteId.value })),
  { textoSoFoto: t('AGENTS.JORNADA.CRIAR.CONFIRA.FOTO') }
);
// O copiloto não tem canal: as caixas só são lidas para quem atende clientes (#1494).
const ocupacao = useCanaisOcupados({ aoMontar: false });
const {
  comecar: comecarAAtender,
  comecando,
  erro: erroDeComecar,
} = useComecarAAtender();
const { podeConectarCanal } = usePermissoesDaJornada();
const podeGerenciar = useCanManage('autonomia_manage');

const registros = useMapGetter('autonomiaAgents/getRecords');
const caixas = useMapGetter('inboxes/getInboxes');
const contaId = useMapGetter('getCurrentAccountId');
const contaDaStore = useMapGetter('accounts/getAccount');

const abrindo = ref(Boolean(idInicial));
const falhouAoAbrir = ref(false);
const elegiveis = ref(null);
const resultado = ref(null);
const exemploAberto = ref(false);
const baseAberta = ref(false);
const internoComecando = ref(false);
const abrindoAjustes = ref(false);
const confirmarSaida = ref(null);
const titulo = ref(null);
const etapaConte = ref(null);
// O campo da conversa é da página: sobrevive à troca de tela no celular, recebe o rascunho de
// "Respondeu errado?" e o texto que não entrou (409).
const rascunhoDaConversa = ref('');

const agente = computed(
  () =>
    (registros.value || []).find(item => item.id === conversa.agenteId.value) ||
    conversa.agenteGerado.value ||
    null
);
const nome = computed(
  () => agente.value?.name || t('AGENTS.JORNADA.COMUM.NOVO_AGENTE')
);
// O rascunho nasce com o nome provisório do backend (Builder#draft_agent: 'Novo agente') e só ganha
// nome quando o Construtor fecha. Até lá a base fala "do agente" (comparação exata, sem regex).
const NOME_DO_RASCUNHO = 'Novo agente';
const semNome = computed(() =>
  [
    undefined,
    null,
    '',
    NOME_DO_RASCUNHO,
    t('AGENTS.JORNADA.COMUM.NOVO_AGENTE'),
  ].includes(agente.value?.name)
);
const modelo = computed(() =>
  modeloDoTipo(agente.value?.agent_type, modeloPedido)
);
const empresa = computed(() => contaDaStore.value?.(contaId.value)?.name || '');
const interno = computed(() =>
  agente.value
    ? agente.value.actuation === ATUACAO.INTERNA
    : atuacaoPedida === ATUACAO.INTERNA
);
const atendendo = computed(
  // #1366: a mesma regra da lista: ativo, ligado e com onde trabalhar (#1433: ou na equipe).
  () => TRABALHANDO.includes(estadoDeAtendimento(agente.value))
);
const fase2 = useFase2();
const equipe = computed(
  () =>
    fase2.value &&
    !interno.value &&
    papelDaQuery(route.query) === PAPEL_AREA_NA_QUERY
);
const salvarEquipe = useSalvarEquipe();

// Onde atender: a leitura L2 (com quem ocupa cada caixa). Se ela falhar, as caixas livres que o
// canal do agente já devolve (sem mostrar as ocupadas).
const semLeitura = computed(() => ocupacao.estado.value === 'erro');
const canais = computed(() =>
  semLeitura.value ? elegiveis.value || [] : ocupacao.canais.value
);
const horarios = computed(() =>
  horariosDasCaixas(canais.value, caixas.value, t)
);
const sugerido = computed(() =>
  canalSugerido(canais.value, conversa.agenteId.value)
);

const carregarElegiveis = async id => {
  try {
    const { data } = await AutonomiaChannelsAPI.get(id);
    elegiveis.value = (data?.eligible_inboxes || []).map(caixa => ({
      inbox_id: caixa.id,
      name: caixa.name,
      channel_type: caixa.channel_type,
      occupied_by: null,
    }));
  } catch {
    elegiveis.value = [];
  }
};

watch(
  () => [semLeitura.value, conversa.agenteId.value],
  ([semL2, id]) => {
    if (semL2 && id && elegiveis.value === null) carregarElegiveis(id);
  }
);

const rotuloComecar = computed(() => {
  if (interno.value) return t('AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_COPILOTO');
  if (equipe.value) return t('AGENTS.JORNADA.EQUIPE.COMECAR');
  if (ocupacao.estado.value === 'carregando') {
    return t('AGENTS.JORNADA.CRIAR.COMECE.COMECAR');
  }
  if (!sugerido.value) return '';
  const tipo = tipoDoCanalParaTexto(sugerido.value);
  const canal = tipo.chave
    ? t(`AGENTS.JORNADA.CRIAR.CANAL.${tipo.chave}`)
    : tipo.nome;
  return t('AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_NO', { canal });
});

const etapaPedida = computed(() => etapaDaQuery(route.query));
const etapa = computed(() => {
  const pedida = etapaPedida.value;
  if (resultado.value) return ETAPA.PRONTO;
  if (pedida === ETAPA.PRONTO && atendendo.value) return ETAPA.PRONTO;
  if (!conversa.fechada.value) return ETAPA.CONTE;
  if (pedida === ETAPA.CONTE && celular.value) return ETAPA.CONTE;
  // O agente da equipe abre o Comece mesmo sem canal livre: a gaveta mostra os bloqueados e o motivo.
  if (
    pedida === ETAPA.COMECE &&
    !interno.value &&
    (equipe.value || canais.value.length)
  ) {
    return ETAPA.COMECE;
  }
  return ETAPA.CONFIRA;
});
const numeroDaEtapa = computed(
  () =>
    ({
      [ETAPA.CONTE]: conversa.fechada.value && !celular.value ? 2 : 1,
      [ETAPA.CONFIRA]: 2,
      [ETAPA.COMECE]: 3,
      [ETAPA.PRONTO]: 4,
    })[etapa.value]
);

const irPara = (proxima, { empilhar = false } = {}) => {
  const query = { ...route.query, etapa: proxima };
  return empilhar ? router.push({ query }) : router.replace({ query });
};

// Computador: ao fechar a conversa, a URL acompanha (Confira) sem trocar de tela.
watch(
  () => conversa.fechada.value,
  fechou => {
    if (fechou && !celular.value && etapaPedida.value === ETAPA.CONTE) {
      irPara(ETAPA.CONFIRA);
    }
  }
);

// Rascunho criado: a query passa a apontar para ele (F5 continua o mesmo).
watch(
  () => conversa.agenteId.value,
  id => {
    if (!id || String(route.query.agente) === String(id)) return;
    const {
      modelo: _modelo,
      type: _type,
      atuacao: _atuacao,
      ...resto
    } = route.query;
    router.replace({ query: { ...resto, agente: String(id) } });
  }
);

// O Construtor mudou o agente depois de um teste: as respostas antigas já não valem.
watch(
  () => conversa.atualizacoes.value,
  () => teste.marcarAtualizado()
);

// Tela nova leva o foco ao título, para teclado e leitor de tela acompanharem: Pronto sempre; no
// celular, cada etapa (é outra tela). No computador, Conte e Confira são a mesma tela e o foco fica
// onde a pessoa estava (no campo); Comece é a folha, que cuida do próprio foco.
watch(etapa, async nova => {
  await nextTick();
  if (nova === ETAPA.PRONTO) {
    document.getElementById('pronto-titulo')?.focus();
  } else if (celular.value && nova !== ETAPA.COMECE) {
    titulo.value?.focus();
  }
});

const exemplo = computed(() => {
  const base = `AGENTS.JORNADA.MODELOS.${exemploDoModelo(modelo.value)}`;
  const hora = (
    MODELOS.find(item => item.i18n === exemploDoModelo(modelo.value)) || {}
  ).horario;
  return [
    { de: 'cliente', texto: t(`${base}.CLIENTE`), hora },
    { de: 'agente', texto: t(`${base}.AGENTE`), hora },
  ];
});
const tituloDoExemplo = computed(() =>
  t(
    interno.value
      ? 'AGENTS.JORNADA.CRIAR.EXEMPLO.TITULO_COPILOTO'
      : 'AGENTS.JORNADA.CRIAR.EXEMPLO.TITULO'
  )
);
const ideias = computed(() =>
  interno.value || modelo.value === MODELO_DO_MEU_JEITO || idInicial
    ? []
    : IDEIAS_PARA_COMECAR.map(chave =>
        t(`AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.${chave}`)
      )
);
const exemploDoCampo = computed(() => {
  if (idInicial) return '';
  if (interno.value) return t('AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_COPILOTO');
  return modelo.value === MODELO_DO_MEU_JEITO
    ? t('AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_DO_MEU_JEITO')
    : '';
});

const propsDaBase = computed(() => ({
  nome: nome.value,
  semNome: semNome.value,
  itens: conversa.base.value,
  estadoDoMaterial: conversa.estadoDoMaterial,
  podeGerenciar: podeGerenciar.value,
  erroAoLer: conversa.erroDaBase.value,
  falhaAoTirar: conversa.falhaAoTirar.value,
}));
const tituloDaBase = computed(() =>
  semNome.value
    ? t('AGENTS.JORNADA.CRIAR.BASE.TITULO_SEM_NOME')
    : t('AGENTS.JORNADA.CRIAR.BASE.TITULO', { nome: nome.value })
);

// A caixa some no Confira (no celular, a gaveta fecha junto com a etapa).
watch(etapa, nova => {
  if (nova !== ETAPA.CONTE) baseAberta.value = false;
});

const linkConectarCanal = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);

const irParaLista = () => router.push({ name: 'autonomia_agents_index' });

const sairDeixandoRascunho = () => {
  const ficou = Boolean(conversa.agenteId.value);
  const nomeAoSair = nome.value;
  irParaLista();
  if (ficou) {
    useAlert(t('AGENTS.JORNADA.CRIAR.SAIR.FEITO', { nome: nomeAoSair }));
  }
};

const voltarParaLista = () => {
  if (!conversa.agenteId.value) {
    irParaLista();
    return;
  }
  confirmarSaida.value?.abrir();
};

const perguntarNoTeste = ({ texto, anexos }) =>
  teste.enviar(texto, anexos || []);

// O campo já foi limpo; se o turno não entrou, o texto volta (a não ser que já tenham escrito outro).
const enviarNaConversa = async carga => {
  const entrou = await conversa.enviar(carga);
  if (!entrou && !rascunhoDaConversa.value) {
    rascunhoDaConversa.value = carga.texto;
  }
};

// Pergunta e resposta vão para o campo da conversa (como em Mudar conversando); a pessoa completa o
// porquê e manda.
const respondeuErrado = async () => {
  const errada = teste.ultima.value;
  if (!errada) return;
  rascunhoDaConversa.value = t(
    'AGENTS.JORNADA.CRIAR.CONFIRA.RESPONDEU_ERRADO_RASCUNHO',
    {
      pergunta: fecharFrase(errada.pergunta),
      nome: nome.value,
      resposta: fecharFrase(errada.resposta),
    }
  );
  if (celular.value) {
    irPara(ETAPA.CONTE, { empilhar: true });
    return;
  }
  await nextTick();
  etapaConte.value?.focar();
};

const ativarInterno = async () => {
  if (internoComecando.value) return;
  internoComecando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: agente.value.id,
      enabled: true,
      status: 'active',
    });
    resultado.value = { canal: '', quando: 'always', saiu: '' };
    irPara(ETAPA.PRONTO);
  } catch {
    useAlert(
      t('AGENTS.JORNADA.CRIAR.COMECE.ERRO_INTERNO', { nome: nome.value })
    );
  } finally {
    internoComecando.value = false;
  }
};

const abrirComece = () => {
  if (interno.value) {
    ativarInterno();
    return;
  }
  erroDeComecar.value = null;
  // Outra aba pode ter ocupado ou liberado uma caixa desde a última leitura.
  ocupacao.carregar();
  irPara(ETAPA.COMECE);
};

// De volta à janela (ex.: conectou um canal na outra aba): relê as caixas quando elas importam.
useEventListener(window, 'focus', () => {
  if (conversa.fechada.value && !interno.value) ocupacao.carregar();
});

const fecharComece = () => {
  if (comecando.value || salvarEquipe.salvando.value) return;
  irPara(ETAPA.CONFIRA);
};

const comecarNoCanal = async ({ inboxId, quando, troca }) => {
  const canal = canais.value.find(item => item.inbox_id === inboxId);
  const feito = await comecarAAtender({
    agente: agente.value,
    inboxId,
    troca,
    janela: quando,
  });
  if (!feito.ok) {
    ocupacao.carregar();
    return;
  }
  resultado.value = {
    canal: canal?.name || '',
    quando,
    saiu: troca?.nome || '',
  };
  irPara(ETAPA.PRONTO);
};

// #1433: grava as caixas da equipe (já liga o agente), relê o agente (estado "Na equipe") e as caixas.
const comecarNaEquipe = async ({ escolhidas, entram, saem }) => {
  const id = conversa.agenteId.value;
  const feito = await salvarEquipe.salvar({
    agenteId: id,
    nome: nome.value,
    entram,
    saem,
  });
  if (!feito) return;
  resultado.value = {
    canal: '',
    quando: 'always',
    saiu: '',
    equipe: ocupacao.canais.value.filter(canal =>
      escolhidas.includes(canal.inbox_id)
    ),
  };
  irPara(ETAPA.PRONTO);
  ocupacao.carregar();
  try {
    await store.dispatch('autonomiaAgents/show', id);
  } catch {
    // O vínculo já foi gravado; a lista relê o agente ao abrir.
  }
};

// Parado (não rascunho) e sem canal: a página do agente abre com o interruptor desligado e a lista
// mostra "Parado". Nenhuma caixa é ligada aqui. Se não salvar, a pessoa continua no Confira.
const fazerAjustesAvancados = async () => {
  if (abrindoAjustes.value) return;
  const id = agente.value?.id;
  if (!id) {
    useAlert(
      t('AGENTS.JORNADA.CRIAR.CONFIRA.AJUSTES_ERRO', { nome: nome.value })
    );
    return;
  }
  abrindoAjustes.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id,
      enabled: false,
      status: 'paused',
    });
    router.push({ name: 'autonomia_agent_panel', params: { agentId: id } });
  } catch {
    useAlert(
      t('AGENTS.JORNADA.CRIAR.CONFIRA.AJUSTES_ERRO', { nome: nome.value })
    );
  } finally {
    abrindoAjustes.value = false;
  }
};

const verAgente = () =>
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: conversa.agenteId.value },
  });

// Pronto depois de F5: o canal vem da L2 e o "quando" do agente.
const pronto = computed(() => {
  if (resultado.value) return resultado.value;
  const meu = canaisDoAgente(conversa.agenteId.value, ocupacao.canais.value)[0];
  return {
    canal: meu?.name || '',
    quando: agente.value?.config?.response_window || 'always',
    saiu: '',
    equipe: caixasDaEquipe(conversa.agenteId.value, ocupacao.canais.value),
  };
});

const abrirAgenteExistente = async () => {
  abrindo.value = true;
  falhouAoAbrir.value = false;
  try {
    const dados = await store.dispatch('autonomiaAgents/show', idInicial);
    if (dados?.actuation !== ATUACAO.INTERNA) ocupacao.carregar();
    const ativo = dados?.status === 'active' && dados?.enabled === true;
    if (ativo && etapaPedida.value !== ETAPA.PRONTO) {
      router.replace({
        name: 'autonomia_agent_panel',
        params: { agentId: idInicial },
      });
      return;
    }
    if (!ativo) await conversa.continuar(dados);
    else await conversa.continuar({ ...dados, has_instruction: true });
  } catch {
    falhouAoAbrir.value = true;
  } finally {
    abrindo.value = false;
  }
};

onMounted(() => {
  if (props.focarTitulo) nextTick(() => titulo.value?.focus());
  conversa.limpar();
  if (idInicial) {
    abrirAgenteExistente();
    return;
  }
  if (atuacaoPedida !== ATUACAO.INTERNA) ocupacao.carregar();
  conversa.comecar();
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <EtapaPronto
      v-if="etapa === ETAPA.PRONTO"
      :nome="nome"
      :canal="pronto.canal"
      :quando="pronto.quando"
      :saiu="pronto.saiu"
      :ultimo="teste.ultima.value"
      :empresa="empresa"
      :celular="celular"
      :interno="interno"
      :equipe="equipe"
      @ver="verAgente"
      @voltar="irParaLista"
    >
      <section
        v-if="equipe"
        data-onde-pronto
        aria-labelledby="onde-pronto-titulo"
        class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <h2
          id="onde-pronto-titulo"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t('AGENTS.JORNADA.ONDE.TITULO', { nome }) }}
        </h2>
        <ResumoOndeTrabalha :canais="pronto.equipe" :caixas="caixas" />
        <!-- #1433: aqui entra "Escolher de quais funis ele cuida", quando a tela do CRM existir (a rota
          vem do Multifunnel, #1447). Até lá, sem botão. -->
      </section>
    </EtapaPronto>

    <div
      v-else
      class="flex flex-col w-full gap-5 px-4 py-6 mx-auto max-w-6xl md:px-6"
      :class="celular ? '' : 'h-full'"
    >
      <button
        v-if="celular && etapa === ETAPA.CONFIRA"
        type="button"
        data-voltar-conversa
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="irPara(ETAPA.CONTE, { empilhar: true })"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('AGENTS.JORNADA.CRIAR.CONFIRA.VOLTAR_CONVERSA') }}
      </button>
      <button
        v-else
        type="button"
        data-voltar-lista
        class="inline-flex items-center gap-1 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="voltarParaLista"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('AGENTS.JORNADA.CRIAR.VOLTAR') }}
      </button>

      <div
        class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between"
      >
        <h1
          ref="titulo"
          tabindex="-1"
          class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12"
        >
          {{
            celular && etapa === ETAPA.CONFIRA
              ? t(
                  interno
                    ? 'AGENTS.JORNADA.CRIAR.CONFIRA.TITULO_COPILOTO'
                    : 'AGENTS.JORNADA.CRIAR.CONFIRA.TITULO'
                )
              : t('AGENTS.JORNADA.CRIAR.TITULO')
          }}
        </h1>
        <AgentesEtapas :atual="numeroDaEtapa" />
      </div>

      <p v-if="abrindo" role="status" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.CRIAR.CARREGANDO') }}
      </p>
      <AgenteErro
        v-else-if="falhouAoAbrir"
        data-erro-abrir
        :titulo="t('AGENTS.JORNADA.CRIAR.ERRO_ABRIR')"
        :garantia="t('AGENTS.JORNADA.CRIAR.ERRO_ABRIR_GARANTIA')"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="abrirAgenteExistente"
      />

      <div
        v-else
        class="grid grid-cols-1 min-w-0 min-h-0 gap-6 md:grid-cols-[minmax(0,1fr)_24rem] md:flex-1"
      >
        <EtapaConte
          v-if="!celular || etapa === ETAPA.CONTE"
          ref="etapaConte"
          v-model:rascunho="rascunhoDaConversa"
          :falas="conversa.falas.value"
          :estado-do-material="conversa.estadoDoMaterial"
          :pensando="conversa.pensando.value"
          :demorando="conversa.demorando.value"
          :falhou="conversa.falhou.value"
          :aviso="conversa.aviso.value"
          :fechada="conversa.fechada.value"
          :respostas="conversa.respostas.value"
          :ideias="ideias"
          :exemplo-do-campo="exemploDoCampo"
          :celular="celular"
          :interno="interno"
          @enviar="enviarNaConversa"
          @tentar-de-novo="conversa.tentarDeNovo"
          @tirar="conversa.tirar"
        >
          <template v-if="celular" #barra>
            <AgenteBotao
              v-if="conversa.fechada.value"
              data-ver-como
              tamanho="xl"
              bloco
              icone-direita="i-lucide-arrow-right"
              @click="irPara(ETAPA.CONFIRA, { empilhar: true })"
            >
              {{ t('AGENTS.JORNADA.CRIAR.CONTE.VER_COMO', { nome }) }}
            </AgenteBotao>
            <!-- A base continua à mão no Conte, também depois que a conversa fecha. -->
            <div class="flex gap-2">
              <AgenteBotao
                v-if="!conversa.fechada.value"
                data-ver-exemplo
                variante="contorno"
                class="flex-1"
                icone="i-lucide-eye"
                @click="exemploAberto = true"
              >
                {{ t('AGENTS.JORNADA.CRIAR.CONTE.VER_EXEMPLO') }}
              </AgenteBotao>
              <AgenteBotao
                data-abrir-base
                variante="contorno"
                class="flex-1"
                icone="i-lucide-library-big"
                :aria-label="
                  t('AGENTS.JORNADA.CRIAR.BASE.BOTAO_ARIA', {
                    titulo: tituloDaBase,
                    n: conversa.base.value.length,
                  })
                "
                @click="baseAberta = true"
              >
                {{ t('AGENTS.JORNADA.CRIAR.BASE.BOTAO') }}
                <span
                  v-if="conversa.base.value.length"
                  data-contagem-base
                  aria-hidden="true"
                  class="grid px-1.5 text-xs font-semibold rounded-full min-w-5 h-5 place-items-center bg-n-blue-3 text-n-blue-11"
                >
                  {{ conversa.base.value.length }}
                </span>
              </AgenteBotao>
            </div>
          </template>
        </EtapaConte>

        <EtapaConfira
          v-if="conversa.fechada.value && (!celular || etapa !== ETAPA.CONTE)"
          :nome="nome"
          :empresa="empresa"
          :perguntas="perguntasDeTeste(modelo, interno)"
          :interno="interno"
          :mensagens="teste.mensagens.value"
          :digitando="teste.digitando.value"
          :problema="teste.aviso.value?.tipo ?? null"
          :atualizado="teste.atualizado.value"
          :respondidas="teste.respondidas.value"
          :conversa-pensando="conversa.pensando.value"
          :rotulo-comecar="rotuloComecar"
          :texto-comecar="
            equipe ? t('AGENTS.JORNADA.EQUIPE.COMECAR_TEXTO', { nome }) : ''
          "
          :pode-conectar-canal="podeConectarCanal"
          :link-conectar-canal="linkConectarCanal"
          :celular="celular"
          :abrindo-ajustes="abrindoAjustes"
          :carregando-canais="
            !interno && ocupacao.estado.value === 'carregando'
          "
          @perguntar="perguntarNoTeste"
          @tentar-de-novo="teste.tentarDeNovo"
          @limpar="teste.limpar"
          @respondeu-errado="respondeuErrado"
          @comecar="abrirComece"
          @ajustes="fazerAjustesAvancados"
        />

        <aside
          v-else-if="!celular"
          data-exemplo
          aria-labelledby="exemplo-titulo"
          class="flex flex-col min-h-0 gap-4 md:overflow-y-auto md:pb-2"
        >
          <h2
            id="exemplo-titulo"
            class="m-0 text-lg font-semibold text-n-slate-12"
          >
            {{ tituloDoExemplo }}
          </h2>
          <p
            v-if="interno"
            data-exemplo-copiloto
            class="m-0 text-sm text-n-slate-11"
          >
            {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.COPILOTO', { nome }) }}
          </p>
          <template v-else>
            <CelularConversa
              tamanho="mini"
              :mensagens="exemplo"
              :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
              :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
            />
            <p class="m-0 text-sm text-n-slate-11">
              {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.LEGENDA', { nome }) }}
            </p>
          </template>
          <template v-if="conversa.podeTestarAgora.value">
            <AgenteBotao
              data-testar-agora
              variante="contorno"
              class="w-fit"
              @click="conversa.testarAgora"
            >
              {{ t('AGENTS.JORNADA.CRIAR.CONTE.TESTAR_AGORA') }}
            </AgenteBotao>
            <p class="m-0 text-sm text-n-slate-11">
              {{ t('AGENTS.JORNADA.CRIAR.CONTE.TESTAR_AGORA_TEXTO') }}
            </p>
          </template>
          <BaseDaCriacao
            v-bind="propsDaBase"
            class="mt-2"
            @anexar="conversa.anexarArquivo"
            @site="conversa.anexarSite"
            @tirar="conversa.tirar"
            @reler="conversa.carregarBase"
          />
        </aside>
      </div>
    </div>

    <EquipeCanais
      v-if="etapa === ETAPA.COMECE && equipe"
      :nome="nome"
      :sem-nome="semNome"
      :agente-id="conversa.agenteId.value"
      :canais="ocupacao.canais.value"
      :caixas="caixas"
      :leitura="ocupacao.estado.value"
      :salvando="salvarEquipe.salvando.value"
      :erro="salvarEquipe.erro.value"
      :texto-final="t('AGENTS.JORNADA.EQUIPE.COMECAR')"
      :texto-sair="t('AGENTS.JORNADA.EQUIPE.VOLTAR_TESTE')"
      :rotulo-carregando="t('AGENTS.JORNADA.COMUM.COMECANDO')"
      @fechar="fecharComece"
      @reler="ocupacao.carregar()"
      @pronto="comecarNaEquipe"
    />
    <EtapaComece
      v-else-if="etapa === ETAPA.COMECE"
      :nome="nome"
      :agente-id="conversa.agenteId.value"
      :canais="canais"
      :horarios="horarios"
      :sem-leitura="semLeitura"
      :onde-inicial="sugerido?.inbox_id ?? null"
      :quando-inicial="agente?.config?.response_window || 'always'"
      :comecando="comecando"
      :erro="erroDeComecar"
      @fechar="fecharComece"
      @comecar="comecarNoCanal"
    />

    <AgenteGaveta
      v-if="exemploAberto"
      :titulo="tituloDoExemplo"
      @fechar="exemploAberto = false"
    >
      <p v-if="interno" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.COPILOTO', { nome }) }}
      </p>
      <template v-else>
        <CelularConversa
          tamanho="mini"
          :mensagens="exemplo"
          :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
          :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
        />
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.LEGENDA', { nome }) }}
        </p>
      </template>
      <template v-if="conversa.podeTestarAgora.value">
        <AgenteBotao
          variante="contorno"
          class="w-fit"
          @click="
            exemploAberto = false;
            conversa.testarAgora();
          "
        >
          {{ t('AGENTS.JORNADA.CRIAR.CONTE.TESTAR_AGORA') }}
        </AgenteBotao>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.CRIAR.CONTE.TESTAR_AGORA_TEXTO') }}
        </p>
      </template>
    </AgenteGaveta>

    <AgenteGaveta
      v-if="baseAberta"
      :titulo="tituloDaBase"
      @fechar="baseAberta = false"
    >
      <BaseDaCriacao
        v-bind="propsDaBase"
        na-gaveta
        @anexar="conversa.anexarArquivo"
        @site="conversa.anexarSite"
        @tirar="conversa.tirar"
        @reler="conversa.carregarBase"
      />
    </AgenteGaveta>

    <AgenteConfirmacao
      ref="confirmarSaida"
      :titulo="t('AGENTS.JORNADA.CRIAR.SAIR.TITULO')"
      :texto="t('AGENTS.JORNADA.CRIAR.SAIR.TEXTO', { nome })"
      :cancelar="t('AGENTS.JORNADA.CRIAR.SAIR.FICAR')"
      :confirmar="t('AGENTS.JORNADA.CRIAR.SAIR.SAIR')"
      :perigo="false"
      @confirmar="sairDeixandoRascunho"
    />
  </div>
</template>
