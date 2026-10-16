<script setup>
// Áudio no balão com a cara do WhatsApp (#1702): play, a onda do próprio áudio
// (cinza, pintando de verde conforme toca, com a bolinha), o tempo embaixo e a
// foto de quem mandou com o microfone; tocando, a foto vira a velocidade.
// A onda só é calculada quando o balão aparece na tela. Baixar fica no menu da
// mensagem, como no app. Sem a pele, o balão usa o player de sempre.
import {
  computed,
  getCurrentInstance,
  onBeforeUnmount,
  ref,
  useTemplateRef,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../../message/provider.js';
import { BARRAS, carregarOnda, tempoDoAudio } from './ondaDoAudio';

const props = defineProps({
  attachment: { type: Object, required: true },
});

const { t } = useI18n();
const { sender } = useMessageContext();
const { uid } = getCurrentInstance();

// Uma altura por nível, de 4 px (silêncio, ainda visível) a 26 px.
const ALTURAS = [
  'h-[4px]',
  'h-[6px]',
  'h-[8px]',
  'h-[10px]',
  'h-[12px]',
  'h-[14px]',
  'h-[16px]',
  'h-[18px]',
  'h-[20px]',
  'h-[22px]',
  'h-[24px]',
  'h-[26px]',
];
// Enquanto a onda não chega (ou se o arquivo não puder ser lido): barras neutras.
const NEUTRAS = Array.from(
  { length: BARRAS },
  (_, i) => [2, 4, 6, 3, 5, 2, 3][i % 7]
);
const VELOCIDADES = [1, 1.5, 2];
const PULO = 5;

const raiz = useTemplateRef('raiz');
const player = useTemplateRef('player');
const trilha = useTemplateRef('trilha');

const barras = ref(null);
const duracao = ref(0);
const atual = ref(0);
const tocando = ref(false);
const ouvido = ref(false);
const velocidade = ref(1);
const arrastando = ref(false);

const endereco = computed(() => timeStampAppendedURL(props.attachment.dataUrl));

// A onda: uma vez, quando o balão aparece na tela.
const cancelar = new AbortController();
let pediuOnda = false;
const pedirOnda = async () => {
  if (pediuOnda) return;
  pediuOnda = true;
  const onda = await carregarOnda(endereco.value, { signal: cancelar.signal });
  if (!onda) return;
  barras.value = onda.barras;
  if (!duracao.value) duracao.value = onda.duracao;
};
const { stop: pararDeObservar } = useIntersectionObserver(
  raiz,
  ([entrada]) => {
    if (!entrada?.isIntersecting) return;
    pararDeObservar();
    pedirOnda();
  },
  { rootMargin: '200px' }
);
onBeforeUnmount(() => cancelar.abort());

const niveis = computed(() => barras.value || NEUTRAS);
const progresso = computed(() =>
  duracao.value ? Math.min(1, atual.value / duracao.value) : 0
);
const barraAtual = computed(() =>
  Math.min(BARRAS - 1, Math.floor(progresso.value * BARRAS))
);
const mostrarVelocidade = computed(() => tocando.value || atual.value > 0);
const tempo = computed(() =>
  tempoDoAudio(mostrarVelocidade.value ? atual.value : duracao.value)
);

// Arquivo gravado no navegador (WebM/Opus) chega sem duração: pular para o fim
// faz o navegador calcular, e volta ao começo.
const descobrirDuracao = () => {
  const el = player.value;
  if (!el) return;
  if (Number.isFinite(el.duration)) {
    duracao.value = el.duration;
    return;
  }
  const aoAndar = () => {
    el.removeEventListener('timeupdate', aoAndar);
    el.currentTime = 0;
    if (Number.isFinite(el.duration)) duracao.value = el.duration;
  };
  el.addEventListener('timeupdate', aoAndar);
  el.currentTime = Number.MAX_SAFE_INTEGER;
};

useEmitter('pause_playing_audio', quem => {
  if (quem !== uid && tocando.value) player.value?.pause();
});

const tocarOuPausar = async () => {
  const el = player.value;
  if (!el) return;
  pedirOnda();
  if (!el.paused) {
    el.pause();
    return;
  }
  emitter.emit('pause_playing_audio', uid);
  el.playbackRate = velocidade.value;
  await el.play();
};

const irPara = segundos => {
  const el = player.value;
  if (!el || !duracao.value) return;
  const destino = Math.max(0, Math.min(duracao.value, segundos));
  el.currentTime = destino;
  atual.value = destino;
};

const irParaOPonteiro = evento => {
  const caixa = trilha.value?.getBoundingClientRect();
  if (!caixa?.width) return;
  irPara(((evento.clientX - caixa.left) / caixa.width) * duracao.value);
};

const comecarArraste = evento => {
  arrastando.value = true;
  trilha.value?.setPointerCapture?.(evento.pointerId);
  irParaOPonteiro(evento);
};
const arrastar = evento => {
  if (arrastando.value) irParaOPonteiro(evento);
};
const soltar = () => {
  arrastando.value = false;
};

const aoTeclar = evento => {
  const MOVER = { ArrowRight: PULO, ArrowLeft: -PULO };
  if (!(evento.key in MOVER)) return;
  evento.preventDefault();
  irPara(atual.value + MOVER[evento.key]);
};

const trocarVelocidade = () => {
  const proxima =
    VELOCIDADES[
      (VELOCIDADES.indexOf(velocidade.value) + 1) % VELOCIDADES.length
    ];
  velocidade.value = proxima;
  if (player.value) player.value.playbackRate = proxima;
};

const aoTocar = () => {
  tocando.value = true;
  ouvido.value = true;
};

const aoTerminar = () => {
  atual.value = 0;
  velocidade.value = 1;
  if (player.value) player.value.playbackRate = 1;
};

const foto = computed(
  () => sender.value?.thumbnail || sender.value?.avatar_url || ''
);
const nome = computed(() => sender.value?.name || '');
</script>

<template>
  <div ref="raiz" class="flex flex-col w-full" data-audio-do-whatsapp>
    <audio
      ref="player"
      class="hidden"
      preload="metadata"
      playsinline
      :src="endereco"
      @loadedmetadata="descobrirDuracao"
      @timeupdate="atual = player?.currentTime || 0"
      @play="aoTocar"
      @pause="tocando = false"
      @ended="aoTerminar"
    />
    <div class="flex items-center gap-2 w-full min-w-0 py-1 ps-1">
      <button
        type="button"
        class="grid place-content-center size-11 flex-shrink-0 rounded-full text-[#54656F] dark:text-[#AEBAC1] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#00A884]"
        :aria-label="
          tocando
            ? t('CONVERSA_CANAL.AUDIO.PAUSAR')
            : t('CONVERSA_CANAL.AUDIO.TOCAR')
        "
        data-tocar-audio
        @click="tocarOuPausar"
      >
        <Icon
          :icon="tocando ? 'i-ph-pause-fill' : 'i-ph-play-fill'"
          class="size-7"
        />
      </button>

      <div class="flex flex-col flex-1 min-w-0 pt-3">
        <div
          ref="trilha"
          role="slider"
          tabindex="0"
          :aria-label="t('CONVERSA_CANAL.AUDIO.ONDA')"
          :aria-valuemin="0"
          :aria-valuemax="Math.round(duracao)"
          :aria-valuenow="Math.round(atual)"
          :aria-valuetext="tempo"
          class="relative flex items-center justify-between gap-px h-[30px] cursor-pointer touch-none select-none outline-none focus-visible:ring-2 focus-visible:ring-[#00A884] rounded"
          data-onda-do-audio
          @pointerdown="comecarArraste"
          @pointermove="arrastar"
          @pointerup="soltar"
          @pointercancel="soltar"
          @keydown="aoTeclar"
        >
          <span
            v-for="(nivel, indice) in niveis"
            :key="indice"
            class="relative flex items-center justify-center w-[2px] flex-shrink-0 h-full"
          >
            <span
              class="w-[2px] rounded-full"
              :class="[
                ALTURAS[nivel],
                indice <= barraAtual && (tocando || atual > 0)
                  ? 'bg-[#00A884]'
                  : 'bg-[#111B21]/25 dark:bg-white/30',
              ]"
            />
            <span
              v-if="indice === barraAtual"
              class="absolute size-3 rounded-full bg-[#00A884] dark:bg-[#06CF9C]"
              :class="{ 'scale-125': arrastando }"
              aria-hidden="true"
            />
          </span>
        </div>
        <span
          class="mt-0.5 text-[11px] leading-4 tabular-nums text-[#667781] dark:text-[#8696A0]"
          data-tempo-do-audio
        >
          {{ tempo }}
        </span>
      </div>

      <button
        v-if="mostrarVelocidade"
        type="button"
        class="grid place-content-center h-7 min-w-11 px-2 flex-shrink-0 rounded-full bg-[#111B21]/10 dark:bg-white/15 text-[13px] font-semibold text-[#54656F] dark:text-[#E9EDEF]"
        :aria-label="t('CONVERSA_CANAL.AUDIO.VELOCIDADE')"
        data-velocidade-do-audio
        @click="trocarVelocidade"
      >
        {{ `${velocidade}×`.replace('.', ',') }}
      </button>
      <span v-else class="relative flex-shrink-0" aria-hidden="true">
        <Avatar :name="nome" :src="foto" :size="48" rounded-full />
        <span
          class="absolute -bottom-0.5 ltr:-left-1 rtl:-right-1 grid place-content-center"
          :class="
            ouvido ? 'text-[#53BDEB]' : 'text-[#00A884] dark:text-[#06CF9C]'
          "
        >
          <Icon icon="i-ph-microphone-fill" class="size-[18px]" />
        </span>
      </span>
    </div>
    <p
      v-if="attachment.transcribedText"
      class="mt-1 px-2 pb-1 text-[13px] leading-5 break-words text-[#3B4A54] dark:text-[#D1D7DB]"
      data-transcricao-do-audio
    >
      {{ attachment.transcribedText }}
    </p>
  </div>
</template>
