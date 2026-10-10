<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useEventListener, useMediaQuery } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import { useConversaDeCriacao } from '../composables/useConversaDeCriacao';
import { useTesteDoAgente } from '../composables/useTesteDoAgente';
import { useCanaisOcupados } from '../composables/useCanaisOcupados';
import { useComecarAAtender } from '../composables/useComecarAAtender';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';
import {
  ETAPA,
  IDEIAS_PARA_COMECAR,
  etapaDaQuery,
  exemploDoModelo,
  idDaQuery,
  modeloDaQuery,
  modeloDoTipo,
  perguntasDeTeste,
} from '../constants/criacao';
import { MODELO_DO_MEU_JEITO, MODELOS } from '../constants/modelos';
import { canaisDoAgente } from '../utils/estadoDoAgente';
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

// #1181 PR2 — criar agente: Conte · Confira · Comece · Pronto (protótipo T03–T06), atrás da flag
// autonomia_agents_journey (o seletor da rota decide). A etapa vem da query (`?etapa=`), e só vale
// quando já dá para estar nela: sem a conversa fechada fica em Conte; sem uma resposta vista no
// teste, Comece volta para Confira; Pronto só com o agente atendendo.
// - Computador: uma tela só. A conversa fica à esquerda e o celular à direita, que vira teste
//   quando a conversa fecha. Comece é a folha à direita.
// - Celular: uma etapa por tela, sem troca automática. Quando a conversa fecha, a barra embaixo
//   vira "Ver como {nome} responde". O CTA fica fixo embaixo, com 56 px.
// Modelo novo: a conversa abre ao montar (a IA fala primeiro). Assim que o rascunho existe, a query
// troca `?modelo=` por `?agente=`: F5 continua o mesmo rascunho em vez de criar outro (o modelo,
// daí em diante, vem do agent_type do rascunho).
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const celular = useMediaQuery('(max-width: 767px)');

const modeloPedido = modeloDaQuery(route.query);
const idInicial = idDaQuery(route.query);

const conversa = useConversaDeCriacao({ modelo: modeloPedido });
// O rascunho ainda está sendo escrito pelo Construtor: só o id; quem diz "incompleto" é o 422.
const teste = useTesteDoAgente(
  computed(() => ({ id: conversa.agenteId.value })),
  { textoSoFoto: t('AGENTS.JORNADA.CRIAR.CONFIRA.FOTO') }
);
const ocupacao = useCanaisOcupados();
const {
  comecar: comecarAAtender,
  comecando,
  erro: erroDeComecar,
} = useComecarAAtender();
const { podeConectarCanal } = usePermissoesDaJornada();

const registros = useMapGetter('autonomiaAgents/getRecords');
const caixas = useMapGetter('inboxes/getInboxes');
const contaId = useMapGetter('getCurrentAccountId');
const contaDaStore = useMapGetter('accounts/getAccount');

const abrindo = ref(Boolean(idInicial));
const falhouAoAbrir = ref(false);
const elegiveis = ref(null);
const resultado = ref(null);
const exemploAberto = ref(false);
const internoComecando = ref(false);
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
const modelo = computed(() =>
  modeloDoTipo(agente.value?.agent_type, modeloPedido)
);
const empresa = computed(() => contaDaStore.value?.(contaId.value)?.name || '');
const interno = computed(() => agente.value?.actuation === 'internal');
const atendendo = computed(
  () => agente.value?.status === 'active' && agente.value?.enabled === true
);

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
  if (interno.value) return t('AGENTS.JORNADA.CRIAR.COMECE.COMECAR');
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
  if (
    pedida === ETAPA.COMECE &&
    teste.respondidas.value > 0 &&
    !interno.value &&
    canais.value.length
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
    const { modelo: _modelo, type: _type, ...resto } = route.query;
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
const ideias = computed(() =>
  modelo.value === MODELO_DO_MEU_JEITO || idInicial
    ? []
    : IDEIAS_PARA_COMECAR.map(chave =>
        t(`AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.${chave}`)
      )
);
const exemploDoCampo = computed(() =>
  modelo.value === MODELO_DO_MEU_JEITO && !idInicial
    ? t('AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_DO_MEU_JEITO')
    : ''
);

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
  if (conversa.fechada.value) ocupacao.carregar();
});

const fecharComece = () => {
  if (comecando.value) return;
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
  };
});

const abrirAgenteExistente = async () => {
  abrindo.value = true;
  falhouAoAbrir.value = false;
  try {
    const dados = await store.dispatch('autonomiaAgents/show', idInicial);
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
  conversa.limpar();
  if (idInicial) {
    abrirAgenteExistente();
    return;
  }
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
      @ver="verAgente"
      @voltar="irParaLista"
    />

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
              ? t('AGENTS.JORNADA.CRIAR.CONFIRA.TITULO')
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
            <AgenteBotao
              v-else
              data-ver-exemplo
              variante="contorno"
              bloco
              icone="i-lucide-eye"
              @click="exemploAberto = true"
            >
              {{ t('AGENTS.JORNADA.CRIAR.CONTE.VER_EXEMPLO') }}
            </AgenteBotao>
          </template>
        </EtapaConte>

        <EtapaConfira
          v-if="conversa.fechada.value && (!celular || etapa !== ETAPA.CONTE)"
          :nome="nome"
          :empresa="empresa"
          :perguntas="perguntasDeTeste(modelo)"
          :mensagens="teste.mensagens.value"
          :digitando="teste.digitando.value"
          :problema="teste.aviso.value?.tipo ?? null"
          :atualizado="teste.atualizado.value"
          :respondidas="teste.respondidas.value"
          :conversa-pensando="conversa.pensando.value"
          :rotulo-comecar="rotuloComecar"
          :pode-conectar-canal="podeConectarCanal"
          :link-conectar-canal="linkConectarCanal"
          :celular="celular"
          @perguntar="perguntarNoTeste"
          @tentar-de-novo="teste.tentarDeNovo"
          @limpar="teste.limpar"
          @respondeu-errado="respondeuErrado"
          @comecar="abrirComece"
          @depois="sairDeixandoRascunho"
        />

        <aside
          v-else-if="!celular"
          data-exemplo
          aria-labelledby="exemplo-titulo"
          class="flex flex-col gap-4"
        >
          <h2
            id="exemplo-titulo"
            class="m-0 text-lg font-semibold text-n-slate-12"
          >
            {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.TITULO') }}
          </h2>
          <CelularConversa
            tamanho="mini"
            :mensagens="exemplo"
            :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
            :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
          />
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.LEGENDA', { nome }) }}
          </p>
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
        </aside>
      </div>
    </div>

    <EtapaComece
      v-if="etapa === ETAPA.COMECE"
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
      :titulo="t('AGENTS.JORNADA.CRIAR.EXEMPLO.TITULO')"
      @fechar="exemploAberto = false"
    >
      <CelularConversa
        tamanho="mini"
        :mensagens="exemplo"
        :selo="t('AGENTS.JORNADA.MODELOS.EXEMPLO')"
        :rotulo-sr="t('AGENTS.JORNADA.MODELOS.EXEMPLO_SR')"
      />
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.CRIAR.EXEMPLO.LEGENDA', { nome }) }}
      </p>
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
