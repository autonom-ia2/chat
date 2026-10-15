<script setup>
import { computed, nextTick, onMounted, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import GrupoDeCartoes from './GrupoDeCartoes.vue';
import {
  BLOQUEIO_DE_PRINCIPAL,
  principaisPossiveis,
} from '../../utils/ajudante';
import { TRABALHANDO, estadoDeAtendimento } from '../../utils/estadoDoAgente';

// Tema 14 (#1434) — os passos do ajudante ("Ajuda outros agentes"), como no protótipo aprovado (70a963b461,
// rodada 3): (1) quem ele vai ajudar e (2) quando chamar, uma decisão por tela.
// - `modo` 'criar': no começo da criação, antes da conversa (página inteira). Nada é gravado aqui: quem
//   chama guarda a escolha na URL e grava o vínculo quando o ajudante começa a ajudar.
// - `modo` 'mudar': o "Mudar" da página do ajudante (numa gaveta). Quem chama grava.
// Só aparecem agentes terminados que falam com cliente: o Copiloto, outros ajudantes e os rascunhos ficam
// fora; a Cotação aparece bloqueada com o motivo (o servidor também a recusa). No passo 1, o aviso decidido
// pelo Rodrigo (14/10): o que o ajudante sabe e faz pode chegar ao cliente pelas respostas do principal.
// `agentes`: os agentes da conta (store); `leitura`: 'carregando' | 'pronto' | 'erro', da lista deles.
const props = defineProps({
  modo: {
    type: String,
    default: 'criar',
    validator: v => ['criar', 'mudar'].includes(v),
  },
  nome: { type: String, required: true },
  semNome: { type: Boolean, default: false },
  agenteId: { type: Number, default: null },
  agentes: { type: Array, default: () => [] },
  leitura: { type: String, default: 'pronto' },
  // { principais: [ids], quando: '' } — a escolha anterior (criar) ou a atual (mudar).
  inicial: { type: Object, default: () => ({ principais: [], quando: '' }) },
  salvando: { type: Boolean, default: false },
  // { titulo, garantia } da gravação que falhou, ou null (só no mudar).
  erro: { type: Object, default: null },
  textoFinal: { type: String, required: true },
  rotuloCarregando: { type: String, default: '' },
  // Só no mudar: o "Mudar" de "Quando chamar" abre direto no segundo passo.
  comecarEm: {
    type: String,
    default: 'quem',
    validator: v => ['quem', 'quando'].includes(v),
  },
});

const emit = defineEmits(['voltar', 'pronto', 'reler']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.AJUDANTE';
const PASSOS = ['quem', 'quando'];
// Mesmo teto do servidor (Specialist::MAX_DESCRIPTION_LENGTH).
const MAX_QUANDO = 500;
const idDoAviso = `ajudante-aviso-${useId()}`;
const idDoQuando = `ajudante-quando-${useId()}`;

const indice = ref(Math.max(PASSOS.indexOf(props.comecarEm), 0));
const escolhidos = ref([...(props.inicial.principais || [])]);
const quando = ref(props.inicial.quando || '');
// A leitura pode chegar depois de abrir: até a pessoa mexer, a escolha acompanha a inicial.
const mexeu = ref(false);
watch(
  () => [(props.inicial.principais || []).join(','), props.inicial.quando],
  () => {
    if (mexeu.value) return;
    escolhidos.value = [...(props.inicial.principais || [])];
    quando.value = props.inicial.quando || '';
  }
);
const escolher = valor => {
  mexeu.value = true;
  escolhidos.value = valor;
};
const escrever = evento => {
  mexeu.value = true;
  quando.value = evento.target.value;
};
const tituloDoPasso = ref(null);
const passo = computed(() => PASSOS[indice.value]);

const comNome = chave =>
  props.semNome
    ? t(`${NS}.${chave}_SEM_NOME`)
    : t(`${NS}.${chave}`, { nome: props.nome });

const MOTIVO = {
  [BLOQUEIO_DE_PRINCIPAL.COTACAO]: () => t(`${NS}.QUEM.COTACAO`),
};

const opcoes = computed(() =>
  principaisPossiveis(props.agentes, props.agenteId).map(
    ({ agente, bloqueio }) => ({
      valor: agente.id,
      avatar: {
        nome: agente.name || '',
        src: agente.avatar_url,
        tom: TRABALHANDO.includes(estadoDeAtendimento(agente))
          ? 'atendendo'
          : 'neutro',
      },
      titulo: agente.name,
      texto: bloqueio
        ? ''
        : t(
            `AGENTS.JORNADA.STATUS.${estadoDeAtendimento(agente).toUpperCase()}`
          ),
      desabilitada: Boolean(bloqueio),
      motivo: bloqueio ? MOTIVO[bloqueio]() : '',
    })
  )
);
const algumLivre = computed(() =>
  opcoes.value.some(opcao => !opcao.desabilitada)
);
// Só valem os escolhidos que ainda podem ser escolhidos (a URL pode ter ficado velha).
const validos = computed(() =>
  escolhidos.value.filter(id =>
    opcoes.value.some(opcao => opcao.valor === id && !opcao.desabilitada)
  )
);
const frase = computed(() => quando.value.trim());

const podeSeguir = computed(() => {
  if (passo.value === 'quem') return validos.value.length > 0;
  return Boolean(frase.value) && !props.salvando;
});

const focarTitulo = async () => {
  await nextTick();
  tituloDoPasso.value?.focus();
};

const seguir = () => {
  if (!podeSeguir.value) return;
  if (passo.value === 'quando') {
    emit('pronto', { principais: validos.value, quando: frase.value });
    return;
  }
  indice.value += 1;
  focarTitulo();
};

const voltar = () => {
  if (props.salvando) return;
  if (indice.value === 0) {
    emit('voltar');
    return;
  }
  indice.value -= 1;
  focarTitulo();
};

// Na criação é uma tela nova: o foco vai ao título do passo. Na gaveta, a gaveta cuida do foco.
onMounted(() => {
  if (props.modo === 'criar') focarTitulo();
});
</script>

<template>
  <section
    data-ajudante-passos
    :data-passo="passo"
    aria-labelledby="ajudante-passo-titulo"
    class="flex flex-col gap-6"
    :aria-busy="salvando ? 'true' : undefined"
  >
    <header class="flex flex-col gap-2">
      <p
        data-progresso
        class="flex items-center gap-2 m-0 text-sm font-medium text-n-slate-11"
      >
        <span aria-hidden="true" class="flex gap-1">
          <span
            v-for="n in PASSOS.length"
            :key="n"
            class="h-1.5 rounded-full transition-all"
            :class="n <= indice + 1 ? 'w-6 bg-n-blue-11' : 'w-3 bg-n-slate-5'"
          />
        </span>
        {{
          t('AGENTS.JORNADA.EQUIPE.PASSO', {
            n: indice + 1,
            total: PASSOS.length,
          })
        }}
      </p>
      <h2
        id="ajudante-passo-titulo"
        ref="tituloDoPasso"
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none md:text-3xl text-n-slate-12"
      >
        {{
          passo === 'quem' ? comNome('QUEM.TITULO') : comNome('QUANDO.TITULO')
        }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ passo === 'quem' ? t(`${NS}.QUEM.TEXTO`) : comNome('QUANDO.TEXTO') }}
      </p>
    </header>

    <template v-if="passo === 'quem'">
      <p v-if="leitura === 'carregando'" role="status" class="m-0 text-sm">
        {{ t(`${NS}.QUEM.CARREGANDO`) }}
      </p>
      <AgenteErro
        v-else-if="leitura === 'erro'"
        data-erro-ler
        tom="ambar"
        :titulo="t(`${NS}.QUEM.ERRO_LER`)"
        :garantia="t(`${NS}.QUEM.ERRO_LER_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        @acao="emit('reler')"
      />
      <template v-else>
        <GrupoDeCartoes
          v-if="opcoes.length"
          :model-value="escolhidos"
          :rotulo="comNome('QUEM.TITULO')"
          :opcoes="opcoes"
          @update:model-value="escolher"
        />
        <p
          v-if="!algumLivre"
          data-nenhum-principal
          class="p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
        >
          {{ t(`${NS}.QUEM.VAZIO`) }}
        </p>
      </template>
      <p
        :id="idDoAviso"
        data-aviso-ajudante
        role="note"
        class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-iris-2 ring-1 ring-inset ring-n-iris-6 text-n-slate-12"
      >
        <span
          class="i-lucide-info size-5 shrink-0 text-n-iris-11"
          aria-hidden="true"
        />
        {{ comNome('AVISO') }}
      </p>
    </template>

    <div v-else class="flex flex-col gap-2">
      <label :for="idDoQuando" class="text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.QUANDO.ROTULO`) }}
      </label>
      <textarea
        :id="idDoQuando"
        :value="quando"
        data-quando
        rows="3"
        :maxlength="MAX_QUANDO"
        :placeholder="t(`${NS}.QUANDO.EXEMPLO`)"
        class="w-full px-4 py-3 text-base rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 border-0 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-blue-11 !mb-0"
        @input="escrever"
      />
    </div>

    <AgenteErro
      v-if="erro && passo === 'quando'"
      data-erro-salvar
      :titulo="erro.titulo"
      :garantia="erro.garantia"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="seguir"
    />

    <footer
      class="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <AgenteBotao
        data-voltar-ajudante
        variante="fantasma"
        icone="i-lucide-arrow-left"
        :desabilitado="salvando"
        @click="voltar"
      >
        {{ t('AGENTS.JORNADA.EQUIPE.VOLTAR') }}
      </AgenteBotao>
      <AgenteBotao
        data-seguir-ajudante
        tamanho="lg"
        class="max-sm:w-full"
        :icone-direita="passo === 'quem' ? 'i-lucide-arrow-right' : ''"
        :inativo="!podeSeguir"
        :carregando="salvando"
        :rotulo-carregando="rotuloCarregando"
        :aria-describedby="passo === 'quem' ? idDoAviso : undefined"
        @click="seguir"
      >
        {{
          passo === 'quem' ? t('AGENTS.JORNADA.EQUIPE.CONTINUAR') : textoFinal
        }}
      </AgenteBotao>
    </footer>
  </section>
</template>
