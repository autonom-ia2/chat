<script setup>
import { TIPOS_DE_ANEXO } from 'dashboard/store/modules/autonomiaGuide';
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useEventListener } from '@vueuse/core';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';

// Caixa de pergunta própria do Guia, em vez do CopilotInput compartilhado.
// O que muda em relação a ele:
//  - o botão redondo é 44x44 e tem nome acessível — é só ícone, e tooltip
//    leitor de tela não lê;
//  - enquanto uma pergunta está em andamento o campo fica em somente-leitura
//    e aparece um aviso. Antes a segunda pergunta era engolida em silêncio.
//
// #895 — no jeito do WhatsApp: com o campo vazio o botão redondo é o
// microfone; tocou, grava com a onda do som e o relógio; o enviar manda o
// áudio direto, sem passar pelo campo. Fotos entram pelo clipe, colando
// (Ctrl/Cmd+V) ou arrastando para cá.
const props = defineProps({
  // Verdadeiro enquanto a resposta da pergunta anterior não chegou.
  isBusy: {
    type: Boolean,
    default: false,
  },
  // Recebe o texto e devolve `true` quando a pergunta entrou na conversa —
  // só aí o campo é limpo.
  onSend: {
    type: Function,
    required: true,
  },
  // Os anexos que esperam o próximo envio: { id, nome, estado, tipo, previa }.
  arquivos: {
    type: Array,
    default: () => [],
  },
  // #895 — recebe { audio, duracao } da mensagem de voz gravada e devolve
  // `false` quando ela não pôde entrar agora (o áudio fica esperando).
  onEnviarVoz: {
    type: Function,
    default: null,
  },
  // #895 — quantos anexos ainda cabem na conversa. O Guia lê no máximo 5;
  // o que passa disso é recusado com aviso, nunca ignorado em silêncio.
  vagas: {
    type: Number,
    default: Infinity,
  },
});

const emit = defineEmits([
  'anexar',
  'remover',
  'semMicrofone',
  'gravacaoFalhou',
  'gravando',
  'limiteDeAnexos',
]);

const message = ref('');
const textareaRef = ref(null);
const fileRef = ref(null);
const gravadorRef = ref(null);
const enviarVozRef = ref(null);
const arrastando = ref(false);
// O que a região viva anuncia ao leitor de tela: gravando, apagada, enviada.
const anuncio = ref('');

const TIPOS_ACEITOS = TIPOS_DE_ANEXO;

const anexoEsperando = computed(() =>
  props.arquivos.some(arquivo => arquivo.estado !== 'erro')
);
const algumSubindo = computed(() =>
  props.arquivos.some(arquivo => arquivo.estado === 'subindo')
);
const temTexto = computed(() => Boolean(message.value.trim()));

const focarCampo = () => nextTick(() => textareaRef.value?.focus());

// Clipe, colar e arrastar passam todos por aqui: entra só o que cabe, e o
// resto é recusado com um aviso (o Guia lê até 5 arquivos por conversa).
const anexarTodos = files => {
  const lista = Array.from(files || []);
  const cabem = lista.slice(0, Math.max(props.vagas, 0));
  cabem.forEach(file => emit('anexar', file));
  if (lista.length > cabem.length) emit('limiteDeAnexos');
};

// O input de arquivo é escondido; o botão do clipe é o alvo de toque (44x44).
const escolherArquivo = () => {
  if (props.vagas <= 0) {
    emit('limiteDeAnexos');
    return;
  }
  fileRef.value?.click();
};

const arquivoEscolhido = event => {
  anexarTodos(event.target.files);
  event.target.value = '';
};

const adjustHeight = () => {
  if (!textareaRef.value) return;
  textareaRef.value.style.height = 'auto';
  textareaRef.value.style.height = `${textareaRef.value.scrollHeight}px`;
};

const sendMessage = () => {
  if (props.isBusy || algumSubindo.value) return;
  if (!temTexto.value && !anexoEsperando.value) return;
  if (!props.onSend(message.value)) return;
  message.value = '';
  nextTick(adjustHeight);
};

const handleInput = () => {
  nextTick(adjustHeight);
};

const handleEnterKey = event => {
  if (event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

// Colar uma foto (print de tela) anexa a foto; colar texto continua normal.
const colar = event => {
  const files = Array.from(event.clipboardData?.files || []);
  if (!files.length) return;
  event.preventDefault();
  anexarTodos(files);
};

// #895 — falar com o Guia, como no WhatsApp. Some onde o navegador não grava.
const MAX_SEGUNDOS_DE_GRAVACAO = 120;
const podeGravar = computed(
  () =>
    Boolean(props.onEnviarVoz) &&
    typeof window !== 'undefined' &&
    typeof window.MediaRecorder !== 'undefined' &&
    Boolean(navigator.mediaDevices?.getUserMedia)
);
// parada | pedindo (o navegador pede o microfone) | gravando | finalizando
// | esperando (o áudio está pronto e sai assim que o Guia terminar de responder)
const voz = ref('parada');
// O áudio que espera a vez: nenhuma gravação se perde sem a pessoa pedir.
let audioEsperando = null;
const segundos = ref(0);
const gravando = computed(() => voz.value !== 'parada');
const mostraMicrofone = computed(
  () => podeGravar.value && !temTexto.value && !anexoEsperando.value
);

// O gravador avisa o tempo como "mm:ss".
const paraSegundos = tempo => {
  const [minutos, resto] = String(tempo).split(':').map(Number);
  return (minutos || 0) * 60 + (resto || 0);
};

const tempoGravado = computed(() => {
  const minutos = Math.floor(segundos.value / 60);
  const resto = String(segundos.value % 60).padStart(2, '0');
  return `${minutos}:${resto}`;
});

const gravar = () => {
  // Trava já: o botão some e um segundo toque não abre outro microfone.
  if (voz.value !== 'parada' || props.isBusy || !podeGravar.value) return;
  segundos.value = 0;
  voz.value = 'pedindo';
  anuncio.value = '';
};

// #982 — a tela de Automações pode abrir já gravando (a pessoa tocou no
// microfone antes de chegar aqui).
defineExpose({ gravar });

// Entrega o áudio; se o Guia ainda está respondendo, ele espera a vez.
const entregarAudio = () => {
  if (props.isBusy || props.onEnviarVoz(audioEsperando) === false) {
    voz.value = 'esperando';
    return;
  }
  audioEsperando = null;
  voz.value = 'parada';
  anuncio.value = 'enviada';
  focarCampo();
};

const enviarGravacao = () => {
  if (voz.value === 'esperando') {
    entregarAudio();
    return;
  }
  if (voz.value !== 'gravando') return;
  voz.value = 'finalizando';
  gravadorRef.value?.stopRecording();
};

// Apagar desmonta o gravador, e é isso que solta o microfone.
const cancelarGravacao = () => {
  if (!gravando.value) return;
  audioEsperando = null;
  voz.value = 'parada';
  anuncio.value = 'apagada';
  focarCampo();
};

const progressoDaGravacao = tempo => {
  if (voz.value === 'pedindo') {
    voz.value = 'gravando';
    anuncio.value = 'gravando';
    nextTick(() => enviarVozRef.value?.focus());
  }
  segundos.value = paraSegundos(tempo);
  if (segundos.value >= MAX_SEGUNDOS_DE_GRAVACAO) enviarGravacao();
};

const gravacaoPronta = ({ file }) => {
  // Apagada antes de o áudio ficar pronto: não manda nada.
  if (voz.value !== 'finalizando') return;
  audioEsperando = { audio: file, duracao: segundos.value };
  entregarAudio();
};

// O Guia terminou de responder: o áudio que esperava sai sozinho.
watch(
  () => props.isBusy,
  ocupado => {
    if (!ocupado && voz.value === 'esperando') entregarAudio();
  }
);

// O painel precisa saber que há gravação: enquanto houver, nenhuma outra
// mensagem sai (ela descartaria o áudio).
watch(gravando, valor => emit('gravando', valor));
onBeforeUnmount(() => {
  if (gravando.value) emit('gravando', false);
});

// O microfone não abriu (permissão negada ou sem aparelho).
const semMicrofone = () => {
  voz.value = 'parada';
  emit('semMicrofone');
  focarCampo();
};

// O áudio gravado não ficou pronto para enviar.
const erroNaGravacao = () => {
  voz.value = 'parada';
  emit('gravacaoFalhou');
  focarCampo();
};

// Esc apaga a gravação. Na fase de captura e sem deixar seguir: o mesmo Esc
// fecharia o painel do Guia inteiro.
useEventListener(
  window,
  'keydown',
  event => {
    if (event.key !== 'Escape' || !gravando.value) return;
    event.stopPropagation();
    event.preventDefault();
    cancelarGravacao();
  },
  { capture: true }
);

// Arrastar fotos e arquivos para a caixa de digitar.
const arrastarPorCima = event => {
  if (gravando.value || props.isBusy) return;
  if (!Array.from(event.dataTransfer?.types || []).includes('Files')) return;
  arrastando.value = true;
};

const soltar = event => {
  arrastando.value = false;
  if (gravando.value || props.isBusy) return;
  anexarTodos(event.dataTransfer?.files);
};

onMounted(() => {
  nextTick(adjustHeight);
});
</script>

<template>
  <div
    class="relative rounded-lg"
    :class="arrastando ? 'ring-2 ring-n-blue-11' : ''"
    @dragover.prevent="arrastarPorCima"
    @dragleave="arrastando = false"
    @drop.prevent="soltar"
  >
    <!-- Os anexos esperando o próximo envio. Depois de enviados, vão para o
         balão da mensagem e o Guia continua lendo todos a cada pergunta. -->
    <ul v-if="arquivos.length" class="flex flex-wrap gap-2 mb-2 p-0 list-none">
      <li
        v-for="arquivo in arquivos"
        :key="arquivo.id"
        class="flex items-center gap-2 max-w-full rounded-lg border border-n-weak bg-n-alpha-1 ltr:pl-1 rtl:pr-1 text-sm"
        :class="
          arquivo.estado === 'erro' ? 'text-n-ruby-11' : 'text-n-slate-12'
        "
      >
        <span class="relative size-9 shrink-0 flex items-center justify-center">
          <img
            v-if="arquivo.tipo === 'imagem' && arquivo.previa"
            :src="arquivo.previa"
            alt=""
            class="size-9 rounded-md object-cover"
            :class="arquivo.estado === 'subindo' ? 'opacity-50' : ''"
          />
          <span
            v-else-if="arquivo.estado !== 'subindo'"
            class="i-lucide-file-text size-5 text-n-slate-11"
            aria-hidden="true"
          />
          <span
            v-if="arquivo.estado === 'subindo'"
            class="absolute i-svg-spinner size-4"
            aria-hidden="true"
          />
        </span>
        <span class="truncate min-w-0">{{ arquivo.nome }}</span>
        <span v-if="arquivo.estado === 'subindo'" class="sr-only">
          {{ $t('AUTONOMIA_GUIDE.FILE.UPLOADING') }}
        </span>
        <span v-if="arquivo.estado === 'erro'" class="sr-only">
          {{ $t('AUTONOMIA_GUIDE.FILE.FAILED') }}
        </span>
        <button
          type="button"
          :aria-label="
            $t('AUTONOMIA_GUIDE.FILE.REMOVE', { nome: arquivo.nome })
          "
          class="h-11 w-11 shrink-0 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-ruby-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
          @click="emit('remover', arquivo.id)"
        >
          <i class="i-lucide-x" />
        </button>
      </li>
    </ul>

    <!-- Gravando: a barra toma o lugar do campo, como no WhatsApp. -->
    <div
      v-if="gravando"
      data-gravacao
      class="flex items-center gap-1 rounded-lg border border-n-weak bg-n-alpha-3 p-1"
    >
      <button
        type="button"
        :aria-label="$t('AUTONOMIA_GUIDE.VOICE.CANCEL')"
        class="h-11 w-11 shrink-0 flex items-center justify-center rounded-full text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-alpha-2 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
        @click="cancelarGravacao"
      >
        <i class="i-lucide-trash-2 size-5" />
      </button>
      <span
        class="size-2.5 shrink-0 rounded-full bg-n-ruby-9"
        :class="voz === 'gravando' ? 'animate-pulse' : 'opacity-40'"
        aria-hidden="true"
      />
      <span class="shrink-0 text-sm tabular-nums text-n-slate-12">
        {{ tempoGravado }}
      </span>
      <div class="flex-1 min-w-0 h-11 overflow-hidden" aria-hidden="true">
        <AudioRecorder
          ref="gravadorRef"
          :audio-record-format="AUDIO_FORMATS.OGG"
          :wave-height="36"
          @recorder-progress-changed="progressoDaGravacao"
          @finish-record="gravacaoPronta"
          @mic-error="semMicrofone"
          @record-error="erroNaGravacao"
        />
      </div>
      <button
        ref="enviarVozRef"
        type="button"
        :disabled="voz !== 'gravando' && !(voz === 'esperando' && !isBusy)"
        :aria-label="$t('AUTONOMIA_GUIDE.VOICE.SEND')"
        class="h-11 w-11 shrink-0 flex items-center justify-center rounded-full bg-n-brand text-white hover:opacity-90 focus-visible:outline-2 focus-visible:outline focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-50"
        @click="enviarGravacao"
      >
        <span
          v-if="voz === 'finalizando'"
          class="i-svg-spinner size-5"
          aria-hidden="true"
        />
        <i v-else class="i-ph-paper-plane-right-fill size-5" />
      </button>
    </div>

    <form v-else class="relative" @submit.prevent="sendMessage">
      <input
        ref="fileRef"
        type="file"
        multiple
        class="hidden"
        :accept="TIPOS_ACEITOS"
        @change="arquivoEscolhido"
      />
      <button
        type="button"
        :disabled="isBusy"
        :aria-label="$t('AUTONOMIA_GUIDE.FILE.ATTACH')"
        class="absolute ltr:left-1 rtl:right-1 top-1/2 -translate-y-1/2 h-11 w-11 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-blue-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-60"
        @click="escolherArquivo"
      >
        <i class="i-lucide-paperclip" />
      </button>
      <textarea
        ref="textareaRef"
        v-model="message"
        :readonly="isBusy"
        :aria-busy="isBusy ? 'true' : 'false'"
        :placeholder="$t('CAPTAIN.COPILOT.SEND_MESSAGE')"
        class="w-full reset-base bg-n-alpha-3 ltr:pl-12 ltr:pr-14 rtl:pl-14 rtl:pr-12 py-3 text-sm border border-n-weak rounded-lg focus:outline-0 focus:outline-none focus:ring-2 focus:ring-n-blue-11 focus:border-n-blue-11 resize-none overflow-y-auto max-h-[200px] mb-0 text-n-slate-12 read-only:cursor-wait read-only:opacity-60"
        rows="1"
        @input="handleInput"
        @paste="colar"
        @keydown.enter.exact="handleEnterKey"
      />
      <!-- Campo vazio e nada anexado: o botão redondo é o microfone. -->
      <button
        v-if="mostraMicrofone"
        type="button"
        :disabled="isBusy"
        :aria-label="$t('AUTONOMIA_GUIDE.VOICE.START')"
        class="absolute ltr:right-1 rtl:left-1 top-1/2 -translate-y-1/2 h-11 w-11 flex items-center justify-center rounded-full bg-n-brand text-white hover:opacity-90 focus-visible:outline-2 focus-visible:outline focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-50"
        @click="gravar"
      >
        <i class="i-lucide-mic size-5" />
      </button>
      <button
        v-else
        :disabled="isBusy || algumSubindo"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.SEND')"
        class="absolute ltr:right-1 rtl:left-1 top-1/2 -translate-y-1/2 h-11 w-11 flex items-center justify-center rounded-full bg-n-brand text-white hover:opacity-90 focus-visible:outline-2 focus-visible:outline focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 disabled:cursor-not-allowed disabled:opacity-50"
        type="submit"
      >
        <i class="i-ph-arrow-up-bold size-5" />
      </button>
    </form>

    <p
      v-if="arrastando"
      class="absolute inset-0 m-0 flex items-center justify-center rounded-lg bg-n-alpha-3 text-sm font-medium text-n-blue-11 pointer-events-none"
    >
      {{ $t('AUTONOMIA_GUIDE.FILE.DROP') }}
    </p>
    <!-- Região viva: quem usa leitor de tela ouve o que mudou na gravação. -->
    <p class="sr-only" role="status" aria-live="polite">
      <template v-if="anuncio === 'gravando'">
        {{ $t('AUTONOMIA_GUIDE.VOICE.RECORDING') }}
      </template>
      <template v-else-if="anuncio === 'apagada'">
        {{ $t('AUTONOMIA_GUIDE.VOICE.CANCELLED') }}
      </template>
      <template v-else-if="anuncio === 'enviada'">
        {{ $t('AUTONOMIA_GUIDE.VOICE.SENT') }}
      </template>
    </p>
    <p
      v-if="voz === 'esperando'"
      class="mt-1 mb-0 text-sm text-n-slate-11"
      role="status"
    >
      {{ $t('AUTONOMIA_GUIDE.VOICE.WAITING') }}
    </p>
    <p v-if="algumSubindo" class="mt-1 mb-0 text-sm text-n-slate-11">
      {{ $t('AUTONOMIA_GUIDE.FILE.WAIT') }}
    </p>
    <!-- Aviso, não só o campo travado: quem digita rápido não repara na
         opacidade e ficava sem nenhum sinal de que a pergunta não saiu. -->
    <p v-if="isBusy" class="mt-1 mb-0 text-sm text-n-slate-11">
      {{ $t('AUTONOMIA_GUIDE.SENDING') }}
    </p>
  </div>
</template>
