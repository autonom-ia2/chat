<script setup>
import { ref, computed, getCurrentInstance } from 'vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';

// #895 — a mensagem de voz do Guia, no jeito do WhatsApp: play redondo de
// 44px, barra que se toca, arrasta e anda com as setas, tempo m:ss e a
// velocidade 1× → 1,5× → 2×. Não usa o AudioPlayer da conversa: lá os botões
// são menores que 44px e ele é compartilhado com o atendimento.
const props = defineProps({
  src: {
    type: String,
    required: true,
  },
  // Duração medida na gravação. O navegador às vezes não sabe a duração de
  // um áudio gravado (devolve Infinity) — aí vale esta.
  duracao: {
    type: Number,
    default: 0,
  },
});

const VELOCIDADES = [1, 1.5, 2];
// Quanto as setas andam na barra.
const PASSO_DAS_SETAS = 5;

const audioRef = ref(null);
const { uid } = getCurrentInstance();

const tocando = ref(false);
const atual = ref(0);
const duracaoDoAudio = ref(0);
const velocidade = ref(1);

const total = computed(() => duracaoDoAudio.value || props.duracao || 0);

const emMinutos = segundos => {
  const inteiro = Math.max(0, Math.floor(segundos || 0));
  return `${Math.floor(inteiro / 60)}:${String(inteiro % 60).padStart(2, '0')}`;
};

const tempoAtual = computed(() => emMinutos(atual.value));
const tempoTotal = computed(() => emMinutos(total.value));

const aoCarregar = () => {
  const medida = audioRef.value?.duration;
  if (Number.isFinite(medida) && medida > 0) duracaoDoAudio.value = medida;
};

const aoAndar = () => {
  atual.value = audioRef.value?.currentTime || 0;
};

const aoTerminar = () => {
  tocando.value = false;
  atual.value = 0;
};

const pausar = () => {
  audioRef.value?.pause();
  tocando.value = false;
};

// Um áudio por vez: o mesmo aviso que o player da conversa usa.
useEmitter('pause_playing_audio', quemTocou => {
  if (quemTocou !== uid && tocando.value) pausar();
});

const tocar = async () => {
  emitter.emit('pause_playing_audio', uid);
  tocando.value = true;
  try {
    await audioRef.value.play();
  } catch {
    tocando.value = false;
  }
};

const alternar = () => (tocando.value ? pausar() : tocar());

const irPara = segundos => {
  const destino = Math.min(Math.max(segundos, 0), total.value || segundos);
  if (audioRef.value) audioRef.value.currentTime = destino;
  atual.value = destino;
};

const aoMoverBarra = event => irPara(Number(event.target.value));

const trocarVelocidade = () => {
  const indice = VELOCIDADES.indexOf(velocidade.value);
  velocidade.value = VELOCIDADES[(indice + 1) % VELOCIDADES.length];
  if (audioRef.value) audioRef.value.playbackRate = velocidade.value;
};
</script>

<template>
  <div class="flex items-center gap-2 w-full min-w-0">
    <audio
      ref="audioRef"
      class="hidden"
      preload="metadata"
      :src="src"
      @loadedmetadata="aoCarregar"
      @durationchange="aoCarregar"
      @timeupdate="aoAndar"
      @ended="aoTerminar"
    />
    <button
      type="button"
      :aria-label="
        tocando
          ? $t('AUTONOMIA_GUIDE.VOICE.PAUSE')
          : $t('AUTONOMIA_GUIDE.VOICE.PLAY')
      "
      class="h-11 w-11 shrink-0 flex items-center justify-center rounded-full bg-n-brand text-white hover:opacity-90 focus-visible:outline-2 focus-visible:outline focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      @click="alternar"
    >
      <i
        class="size-5"
        :class="tocando ? 'i-ph-pause-fill' : 'i-ph-play-fill'"
        aria-hidden="true"
      />
    </button>
    <div class="flex flex-col flex-1 min-w-0">
      <input
        type="range"
        min="0"
        :max="total"
        step="any"
        :value="atual"
        :aria-label="$t('AUTONOMIA_GUIDE.VOICE.POSITION')"
        :aria-valuetext="
          $t('AUTONOMIA_GUIDE.VOICE.POSITION_VALUE', {
            atual: tempoAtual,
            total: tempoTotal,
          })
        "
        class="w-full h-11 m-0 cursor-pointer accent-n-brand focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
        @input="aoMoverBarra"
        @keydown.left.prevent="irPara(atual - PASSO_DAS_SETAS)"
        @keydown.right.prevent="irPara(atual + PASSO_DAS_SETAS)"
      />
      <span
        class="-mt-2 text-xs tabular-nums text-n-slate-11"
        aria-hidden="true"
      >
        {{
          $t('AUTONOMIA_GUIDE.VOICE.TIME', {
            atual: tempoAtual,
            total: tempoTotal,
          })
        }}
      </span>
    </div>
    <button
      type="button"
      class="h-11 min-w-11 shrink-0 px-2 flex items-center justify-center rounded-full bg-n-alpha-2 text-xs font-semibold tabular-nums text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
      @click="trocarVelocidade"
    >
      <span class="sr-only">{{ $t('AUTONOMIA_GUIDE.VOICE.SPEED') }}</span>
      <template v-if="velocidade === 1">
        {{ $t('AUTONOMIA_GUIDE.VOICE.SPEED_1') }}
      </template>
      <template v-else-if="velocidade === 1.5">
        {{ $t('AUTONOMIA_GUIDE.VOICE.SPEED_1_5') }}
      </template>
      <template v-else>
        {{ $t('AUTONOMIA_GUIDE.VOICE.SPEED_2') }}
      </template>
    </button>
  </div>
</template>
