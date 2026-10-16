<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AutonomiaChannelsAPI from 'dashboard/api/autonomia/channels';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import EscolhaRadio from '../EscolhaRadio.vue';
import OndeQuandoEscolha from '../OndeQuandoEscolha.vue';
import NotaHorarioDoCanal from '../NotaHorarioDoCanal.vue';
import { useHorarioUnicoCaixa } from 'dashboard/composables/useHorarioUnicoCaixa';
import NotaQuemRecebe from './NotaQuemRecebe.vue';
import TambemRecebe from '../onde/TambemRecebe.vue';
import {
  MOTIVO,
  useComecarAAtender,
} from '../../composables/useComecarAAtender';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import { trocaNoCanal } from '../../utils/canais';
import { outrasCaixasDaEquipe } from '../../utils/ondeTrabalha';
import { useAgenteIaPorCaixa } from '../../composables/useAgenteIaPorCaixa';
import { QUANDO, quandoDoAgente } from '../../utils/pagina';

// #1181 PR3 (protótipo T10 e "Voltar a atender") — onde e quando o agente responde.
// - modo 'alterar', atendendo: escolher a caixa (livre ou ocupada, com troca) e o "quando". O "Salvar"
//   é um pedido só (#1720, PUT onde_atende), que o servidor grava numa transação.
// - modo 'alterar', parado (t10-parado): a caixa fica só para ler, com "Voltar a atender"; o
//   "quando" continua editável.
// - modo 'voltar' (T15 voltar): a mesma confirmação de canal do Começar a atender, com a caixa atual
//   marcada. Se ela continua ligada ao agente, só o PATCH active; senão a sequência completa.
// Sem canal conectado na conta (t10-semcanal): o link para conectar, só para quem pode; o "quando"
// e a nota de Atribuição continuam (salvar grava só a janela). Enquanto as caixas chegam, um
// carregando; se a leitura falhou, o erro padrão com "Tentar de novo" (`reler`), nunca o "não
// conectou nenhum canal". A caixa atual entra marcada quando chega, se a pessoa ainda não escolheu.
// #1433 (decisão do Rodrigo de 15/10, "a, para todos os agentes"): com `recebeEmOutras`, logo abaixo de
// "Onde atende" vem "Também recebe quando alguém passar em:" (TambemRecebe), as outras caixas em que ele
// fica como agente da equipe. Só no 'alterar' atendendo e com a leitura das caixas (L2): entrar numa
// área liga o agente, então o agente parado não vê a seção.
// #1720 (desenho do Rodrigo de 16/10) — "Onde atende" vira "{nome} atende primeiro as conversas novas?":
// "Sim, no canal:" ou "Não, só quando alguém passar a conversa". O "Não" tira o agente das caixas em
// que atende primeiro e deixa só "Recebe quando alguém passar em:". Um "Salvar" aplica tudo. "Não" sem
// nenhuma caixa marcada pede confirmação em linha, no rodapé, antes de gravar (o servidor também recusa
// sem ela: confirmar_parado). Sai o botão "Não atender em nenhum lugar". Todo agente usa esta gaveta,
// inclusive o que está só na equipe (na_equipe). A pergunta só aparece com a seção "Recebe quando…"
// (Fase 2 e a leitura das caixas); sem ela, a escolha de canal de sempre e as áreas ficam como estão.
// Um "Salvar" só: AutonomiaChannelsAPI.ondeAtende, numa transação no servidor. Recusado (422), nada
// mudou e a tela mostra a explicação do servidor (inclusive a de não conseguir sair do canal antigo).
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  modo: {
    type: String,
    default: 'alterar',
    validator: v => ['alterar', 'voltar'].includes(v),
  },
  atendendo: { type: Boolean, default: false },
  canais: { type: Array, required: true },
  // Estado da leitura das caixas (useCanaisDoAgente): 'carregando' | 'pronto' | 'erro'.
  estadoCanais: { type: String, default: 'pronto' },
  atuais: { type: Array, default: () => [] },
  semLeitura: { type: Boolean, default: false },
  horarios: { type: Object, default: () => ({}) },
  // #1433: mostra "Também recebe quando alguém passar em:" (agente que fala com cliente, Fase 2 ligada).
  recebeEmOutras: { type: Boolean, default: false },
  // Ids das caixas em que ele já está na equipe (área), pela L2.
  equipeAtual: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
});

const emit = defineEmits(['fechar', 'pronto', 'voltarAAtender', 'reler']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { podeConectarCanal } = usePermissoesDaJornada();
const { ligado: horarioUnico } = useHorarioUnicoCaixa();
const { comecar, comecando } = useComecarAAtender();
const NS = 'AGENTS.JORNADA.PAGINA.ONDE';

const inboxAtual = computed(() => props.atuais[0]?.inbox_id ?? null);
const onde = ref(inboxAtual.value);
// #1720: 'sim' (atende primeiro no canal `onde`) ou 'nao' (só quando alguém passar).
const primeiroDe = inboxId => (inboxId ? 'sim' : 'nao');
const primeiro = ref(primeiroDe(inboxAtual.value));
const escolheu = ref(false);
watch(inboxAtual, atual => {
  if (escolheu.value) return;
  onde.value = atual;
  primeiro.value = primeiroDe(atual);
});
const escolherOnde = inboxId => {
  escolheu.value = true;
  onde.value = inboxId;
};
const escolherPrimeiro = valor => {
  escolheu.value = true;
  primeiro.value = valor;
};
// Aviso em linha do "Não" sem nenhuma caixa: aberto até "Deixar parado" ou "Voltar".
const avisoParado = ref(false);
const quando = ref(quandoDoAgente(props.agente));
// Outras caixas marcadas. A leitura pode chegar depois de abrir: até a pessoa mexer, acompanha a atual.
const outras = ref([...props.equipeAtual]);
const mexeuNasOutras = ref(false);
watch(
  () => props.equipeAtual.join(','),
  () => {
    if (!mexeuNasOutras.value) outras.value = [...props.equipeAtual];
  }
);
const escolherOutras = valor => {
  mexeuNasOutras.value = true;
  outras.value = valor;
};
const salvando = ref(false);
const erro = ref(null);

const voltar = computed(() => props.modo === 'voltar');
const somenteLeitura = computed(() => !voltar.value && !props.atendendo);
const ocupado = computed(() => salvando.value || comecando.value);
const carregandoCanais = computed(
  () => props.estadoCanais === 'carregando' && !props.canais.length
);
const erroCanais = computed(() => props.estadoCanais === 'erro');
const semCanal = computed(
  () => props.estadoCanais === 'pronto' && !props.canais.length
);
const semLista = computed(() => carregandoCanais.value || erroCanais.value);
const mostrarOutras = computed(
  () =>
    props.recebeEmOutras &&
    !voltar.value &&
    !somenteLeitura.value &&
    !props.semLeitura &&
    !semLista.value &&
    !semCanal.value
);
// "{nome} atende primeiro…?" só com a seção "Recebe quando…" à vista.
const soQuandoPassar = computed(
  () => mostrarOutras.value && primeiro.value === 'nao'
);
// #1648 — com a aba "Agente de IA" por caixa, o canal com agente de outro sistema aceita.
const porCaixa = useAgenteIaPorCaixa();
// Fora da lista: no "Sim", as caixas em que ele é o principal agora e a escolhida. No "Não" ele sai
// delas, então todas podem ser marcadas (a em que ainda é principal sai pelo outrasCaixasDaEquipe).
const foraDasOutras = computed(() =>
  soQuandoPassar.value
    ? []
    : [...props.atuais.map(canal => canal.inbox_id), onde.value].filter(
        id => id !== null && id !== undefined
      )
);
// Só valem as marcadas que ainda podem ser escolhidas (e nunca a caixa principal escolhida).
const outrasValidas = computed(() => {
  const livres = outrasCaixasDaEquipe(
    props.canais,
    props.agente.id,
    foraDasOutras.value,
    { comOutroSistema: porCaixa.value }
  )
    .filter(({ bloqueio }) => !bloqueio)
    .map(({ canal }) => canal.inbox_id);
  return outras.value.filter(id => livres.includes(id));
});
const troca = computed(() =>
  soQuandoPassar.value
    ? null
    : trocaNoCanal(props.canais, onde.value, props.agente.id)
);
// Com a lista de canais à vista, o "Sim" precisa de um canal escolhido.
const faltaCanal = computed(
  () =>
    !somenteLeitura.value &&
    !semCanal.value &&
    !soQuandoPassar.value &&
    !onde.value
);
// No "Não", sem caixa marcada em "Recebe quando…", ele não fica em lugar nenhum.
const ficaParado = computed(
  () => soQuandoPassar.value && !outrasValidas.value.length
);
const nomeDoCanal = inboxId =>
  props.canais.find(canal => canal.inbox_id === inboxId)?.name || '';

const linkConectar = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);

// Quando, para o agente parado (sem a escolha de caixa): mesmas opções do OndeQuandoEscolha.
const horarioAtual = computed(() =>
  inboxAtual.value in props.horarios
    ? props.horarios[inboxAtual.value]
    : undefined
);
const ROTULO_QUANDO = {
  always: 'SEMPRE',
  business_hours: 'DENTRO',
  outside_business_hours: 'FORA',
};
const opcoesQuando = computed(() =>
  QUANDO.map(valor => {
    const chave = ROTULO_QUANDO[valor];
    let texto = '';
    if (valor === 'always') {
      texto = t('AGENTS.JORNADA.ONDE_QUANDO.SEMPRE_TEXTO');
    } else if (horarioAtual.value) {
      texto = t(`AGENTS.JORNADA.ONDE_QUANDO.${chave}_TEXTO`, {
        horario: horarioAtual.value,
      });
    }
    return {
      valor,
      titulo: t(`AGENTS.JORNADA.ONDE_QUANDO.${chave}`),
      texto,
      desabilitada: valor !== 'always' && horarioAtual.value === null,
    };
  })
);

const ERRO_DO_MOTIVO = {
  [MOTIVO.CANAL]: () => ({
    titulo: t('AGENTS.JORNADA.ERRO.CANAL'),
    garantia: t('AGENTS.JORNADA.ERRO.CANAL_GARANTIA'),
    acao: t('AGENTS.JORNADA.ERRO.CANAL_ACAO'),
    escolherOutro: true,
  }),
  [MOTIVO.TROCA_SEM_AGENTE]: resultado => ({
    titulo: t('AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE', { nome: props.nome }),
    garantia: t('AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE_GARANTIA', {
      canal: resultado.troca?.canal,
    }),
  }),
  [MOTIVO.OFFLINE]: () => ({
    titulo: t('AGENTS.JORNADA.ERRO.OFFLINE'),
    garantia: t('AGENTS.JORNADA.ERRO.OFFLINE_GARANTIA'),
    ambar: true,
  }),
};

const erroGeralDeComecar = resultado => {
  const doMotivo = ERRO_DO_MOTIVO[resultado.motivo];
  if (doMotivo) return doMotivo(resultado);
  if (!voltar.value) {
    return { titulo: t(`${NS}.ERRO`), garantia: t(`${NS}.ERRO_GARANTIA`) };
  }
  return {
    titulo: t('AGENTS.JORNADA.ERRO.COMECAR_ATENDER'),
    garantia: t('AGENTS.JORNADA.ERRO.COMECAR_ATENDER_GARANTIA', {
      nome: props.nome,
    }),
  };
};

// #1366: o servidor explicou a recusa (422): a explicação dele no lugar do título geral.
const erroDeComecar = resultado => {
  const geral = erroGeralDeComecar(resultado);
  return resultado.mensagem ? { ...geral, titulo: resultado.mensagem } : geral;
};

const erroDeSalvar = () => ({
  titulo: t(`${NS}.ERRO`),
  garantia: t(`${NS}.ERRO_GARANTIA`),
});

const terminar = mensagem => {
  useAlert(mensagem);
  emit('pronto');
  emit('fechar');
};

const atualizar = dados =>
  store.dispatch('autonomiaAgents/update', { id: props.agente.id, ...dados });

const janelaMudou = () => quando.value !== quandoDoAgente(props.agente);

const entrarNaCaixa = async () => {
  const resultado = await comecar({
    agente: props.agente,
    inboxId: onde.value,
    troca: troca.value,
    janela: quando.value,
  });
  if (!resultado.ok) erro.value = erroDeComecar(resultado);
  return resultado.ok;
};

// #1720 — o pedido do "Salvar": áreas só com a seção à vista (nulo = ficam como estão).
const pedidoDeSalvar = parar => ({
  primeiroInboxId: soQuandoPassar.value ? null : onde.value,
  areaInboxIds: mostrarOutras.value ? outrasValidas.value : null,
  responseWindow: quando.value,
  parar,
});

const erroDoServidor = falha => {
  const semRede =
    (typeof navigator !== 'undefined' && navigator.onLine === false) ||
    !falha?.response;
  if (semRede) return ERRO_DO_MOTIVO[MOTIVO.OFFLINE]();
  return {
    titulo: falha.response.data?.error || t(`${NS}.ERRO`),
    garantia: t(`${NS}.ERRO_GARANTIA`),
  };
};

// Sem a escolha de canal (agente parado ou sem canal na conta), só o "quando" muda.
const salvarSoAJanela = async () => {
  if (janelaMudou()) {
    await atualizar({ config: { response_window: quando.value } });
  }
  terminar(t(`${NS}.PRONTO`));
};

const salvarAlteracao = async parar => {
  if (somenteLeitura.value || semCanal.value) {
    await salvarSoAJanela();
    return;
  }
  try {
    await AutonomiaChannelsAPI.ondeAtende(
      props.agente.id,
      pedidoDeSalvar(parar)
    );
  } catch (falha) {
    // O servidor pede a confirmação que a tela já pede (outra aba, leitura velha): o mesmo aviso.
    if (falha?.response?.data?.code === 'confirmar_parado') {
      avisoParado.value = true;
      return;
    }
    erro.value = erroDoServidor(falha);
    emit('pronto');
    return;
  }
  terminar(t(`${NS}.PRONTO`));
};

const voltarAAtender = async () => {
  const jaLigado = props.atuais.some(canal => canal.inbox_id === onde.value);
  if (!jaLigado) {
    if (!(await entrarNaCaixa())) return;
  } else {
    const dados = { enabled: true, status: 'active' };
    if (janelaMudou()) dados.config = { response_window: quando.value };
    try {
      await atualizar(dados);
    } catch {
      erro.value = erroDeComecar({ motivo: MOTIVO.COMECAR });
      return;
    }
  }
  terminar(
    t(`${NS}.VOLTOU`, { canal: nomeDoCanal(onde.value), nome: props.nome })
  );
};

const confirmar = async ({ parado = false } = {}) => {
  if (ocupado.value) return;
  if (!voltar.value && ficaParado.value && !parado) {
    avisoParado.value = true;
    return;
  }
  avisoParado.value = false;
  erro.value = null;
  salvando.value = true;
  try {
    if (voltar.value) await voltarAAtender();
    else await salvarAlteracao(parado);
  } catch {
    erro.value = erroDeSalvar();
  } finally {
    salvando.value = false;
  }
};

const acaoDoErro = () => {
  if (erro.value?.escolherOutro) {
    erro.value = null;
    onde.value = inboxAtual.value;
    return;
  }
  confirmar();
};

const deixarParado = () => confirmar({ parado: true });
// Mexer na escolha fecha o aviso: ele vale para a escolha de quando apareceu.
watch([primeiro, outrasValidas], () => {
  avisoParado.value = false;
});

const titulo = computed(() =>
  voltar.value
    ? t('AGENTS.JORNADA.ONDE_QUANDO.TITULO', { nome: props.nome })
    : t(`${NS}.TITULO`, { nome: props.nome })
);
// #1525 — quem não está em canal nenhum (a Lia que nasceu parada, um agente novo) começa a atender; quem
// tem canal e foi parado volta a atender. Critério: nenhum canal atual, nem pela contagem do servidor.
const semCanalAtual = computed(
  () => !props.atuais.length && !props.agente.channels_count
);
const rotuloVoltar = computed(() => {
  if (troca.value) return t(`${NS}.TROCAR`);
  return semCanalAtual.value ? t(`${NS}.COMECAR`) : t(`${NS}.VOLTAR`);
});
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <div class="flex flex-col gap-5" :aria-busy="ocupado ? 'true' : undefined">
      <AgenteErro
        v-if="erro"
        data-erro
        :tom="erro.ambar ? 'ambar' : 'rubi'"
        :titulo="erro.titulo"
        :garantia="erro.garantia"
        :acao="erro.acao || t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="ocupado"
        @acao="acaoDoErro"
      />

      <p
        v-if="carregandoCanais"
        data-carregando-canais
        role="status"
        class="flex items-center gap-2 p-4 m-0 text-sm rounded-2xl bg-n-slate-2 text-n-slate-11"
      >
        <span
          class="i-lucide-loader-circle size-4 shrink-0 motion-safe:animate-spin"
          aria-hidden="true"
        />
        {{ t(`${NS}.CARREGANDO_CANAIS`) }}
      </p>

      <AgenteErro
        v-else-if="erroCanais"
        data-erro-canais
        :titulo="t(`${NS}.LER_ERRO`)"
        :garantia="t(`${NS}.LER_ERRO_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="emit('reler')"
      />

      <template v-else-if="semCanal || somenteLeitura">
        <section class="flex flex-col gap-2">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.ONDE`) }}
          </h3>
          <div
            v-if="semCanal"
            data-sem-canal
            class="flex flex-col gap-2 p-4 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
          >
            <p class="m-0">{{ t(`${NS}.SEM_CANAL`) }}</p>
            <a
              v-if="podeConectarCanal"
              data-conectar
              :href="linkConectar"
              target="_blank"
              rel="noopener noreferrer"
              class="relative inline-flex items-center gap-1 font-semibold underline min-h-11 w-fit text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            >
              {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
              <span class="i-lucide-external-link size-4" aria-hidden="true" />
              <span class="sr-only">{{
                t('AGENTS.JORNADA.COMUM.NOVA_ABA')
              }}</span>
            </a>
            <p v-else class="m-0 text-n-slate-11">
              {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
            </p>
          </div>
          <div v-else data-parado class="flex flex-col gap-2">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{
                nomeDoCanal(inboxAtual) ||
                t('AGENTS.JORNADA.PAGINA.NENHUM_CANAL')
              }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ t(`${NS}.PARADO`, { nome }) }}
            </p>
            <AgenteBotao
              data-voltar
              class="self-start"
              icone="i-lucide-power"
              @click="emit('voltarAAtender')"
            >
              {{ t(`${NS}.VOLTAR`) }}
            </AgenteBotao>
          </div>
        </section>
        <section class="flex flex-col gap-2">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.QUANDO`) }}
          </h3>
          <EscolhaRadio
            v-model="quando"
            :rotulo="t(`${NS}.QUANDO_ROTULO`)"
            :opcoes="opcoesQuando"
          />
          <NotaHorarioDoCanal
            v-if="horarioUnico"
            :inbox-id="inboxAtual"
            :horario="horarioAtual"
          />
        </section>
        <NotaQuemRecebe :nome="nome" />
      </template>

      <template v-else>
        <OndeQuandoEscolha
          v-model:quando="quando"
          :onde="onde"
          :primeiro="mostrarOutras ? primeiro : null"
          :horario-de-cada="soQuandoPassar && outrasValidas.length > 0"
          :canais="canais"
          :agente-id="agente.id"
          :nome="nome"
          :horarios="horarios"
          :sem-leitura="semLeitura"
          @update:onde="escolherOnde"
          @update:primeiro="escolherPrimeiro"
        >
          <template v-if="mostrarOutras" #depoisDeOnde>
            <TambemRecebe
              :agente-id="agente.id"
              :nome="nome"
              :canais="canais"
              :caixas="caixas"
              :fora="foraDasOutras"
              :model-value="outras"
              @update:model-value="escolherOutras"
            />
          </template>
        </OndeQuandoEscolha>
      </template>
    </div>

    <template #rodape>
      <template v-if="voltar">
        <AgenteBotao
          data-confirmar
          tamanho="xl"
          bloco
          :carregando="ocupado"
          :rotulo-carregando="t('AGENTS.JORNADA.COMUM.COMECANDO')"
          :desabilitado="!onde || semCanal || semLista"
          aria-describedby="onde-voltar-texto"
          @click="confirmar"
        >
          {{ rotuloVoltar }}
        </AgenteBotao>
        <p
          id="onde-voltar-texto"
          class="m-0 text-sm text-center text-n-slate-11"
        >
          {{ t(`${NS}.VOLTAR_TEXTO`, { nome }) }}
        </p>
      </template>
      <div
        v-else-if="avisoParado"
        data-aviso-parado
        role="group"
        aria-labelledby="onde-aviso-parado"
        class="flex flex-col gap-3 p-3 rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
      >
        <p
          id="onde-aviso-parado"
          aria-live="polite"
          class="flex items-start gap-2 m-0 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ t(`${NS}.PARADO_AVISO`, { nome }) }}
        </p>
        <div class="flex flex-wrap justify-end gap-2">
          <AgenteBotao
            data-voltar-aviso
            variante="contorno"
            tamanho="lg"
            :desabilitado="ocupado"
            @click="avisoParado = false"
          >
            {{ t(`${NS}.PARADO_VOLTAR`) }}
          </AgenteBotao>
          <AgenteBotao
            data-deixar-parado
            tamanho="lg"
            :carregando="ocupado"
            :rotulo-carregando="t(`${NS}.SALVANDO`)"
            @click="deixarParado"
          >
            {{ t(`${NS}.PARADO_CONFIRMAR`) }}
          </AgenteBotao>
        </div>
      </div>
      <div v-else class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="ocupado"
          @click="emit('fechar')"
        >
          {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          data-confirmar
          tamanho="lg"
          :carregando="ocupado"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          :desabilitado="semLista || faltaCanal"
          @click="confirmar()"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
