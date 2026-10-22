<script setup>
// Mensagem de voz do Direct (#2079): play redondo, a onda de barras que acende
// enquanto toca e a pílula branca com o tempo. Na enviada, ícone e tempo em azul.
// Embaixo, "Ver transcrição" quando o áudio já tem o texto transcrito.
// A onda é ilustrativa (o arquivo da Meta não libera leitura do som pelo navegador):
// alturas fixas por anexo, para cada áudio ter a sua e ela não mudar a cada tela.
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { ENVIADO, RECEBIDO } from './visualInstagram';

const props = defineProps({
  anexo: { type: Object, required: true },
  enviada: { type: Boolean, default: false },
  cantos: { type: Object, required: true },
});

const { t } = useI18n();
const BARRAS = 32;
const ALTURA_MINIMA = 2;
const ALTURA_MAXIMA = 26;
// Gerador simples com semente no id do anexo: mesma onda sempre para o mesmo áudio.
const ondaDoAnexo = id => {
  let semente = Number(id) || 1;
  return Array.from({ length: BARRAS }, () => {
    semente = (semente * 9301 + 49297) % 233280;
    const sorteio = semente / 233280;
    return Math.round(ALTURA_MINIMA + sorteio * sorteio * ALTURA_MAXIMA);
  });
};
const onda = computed(() => ondaDoAnexo(props.anexo.id));
const transcricao = computed(() => (props.anexo.transcribedText || '').trim());
const mostrarTranscricao = ref(false);
const audio = useTemplateRef('audio');
const tocando = ref(false);
const duracao = ref(0);
const atual = ref(0);

const alternar = () => {
  if (!audio.value) return;
  if (tocando.value) audio.value.pause();
  else audio.value.play();
};
const aoCarregar = () => {
  const total = audio.value?.duration;
  duracao.value = Number.isFinite(total) ? total : 0;
};
const aoAndar = () => {
  atual.value = audio.value?.currentTime || 0;
};
const aoAcabar = () => {
  tocando.value = false;
  atual.value = 0;
};

const acesos = computed(() =>
  duracao.value ? Math.round((atual.value / duracao.value) * BARRAS) : 0
);
const tempo = computed(() => {
  const segundos = Math.round(
    tocando.value || atual.value ? atual.value : duracao.value
  );
  const minutos = Math.floor(segundos / 60);
  return `${minutos}:${String(segundos % 60).padStart(2, '0')}`;
});
const cor = computed(() => (props.enviada ? ENVIADO : RECEBIDO));
const corDoDestaque = computed(() =>
  props.enviada ? 'text-[#4A5DF9]' : 'text-[#0C1014]'
);
</script>

<template>
  <div
    class="flex flex-col gap-1 w-[284px] max-w-full px-3 py-2"
    :class="cor"
    :style="cantos"
  >
    <div class="flex items-center gap-2">
      <button
        type="button"
        class="flex items-center justify-center size-6 shrink-0 p-0 rounded-full bg-white"
        :class="corDoDestaque"
        :aria-label="
          t(
            tocando
              ? 'CONVERSA_CANAL.INSTAGRAM.PAUSAR'
              : 'CONVERSA_CANAL.INSTAGRAM.REPRODUZIR'
          )
        "
        @click="alternar"
      >
        <span
          :class="tocando ? 'i-ph-pause-fill' : 'i-ph-play-fill'"
          class="size-3.5 shrink-0"
        />
      </button>
      <span
        class="flex h-7 flex-1 items-center justify-between min-w-0"
        aria-hidden="true"
      >
        <span
          v-for="(altura, indice) in onda"
          :key="indice"
          class="w-0.5 shrink-0 rounded-full bg-current"
          :class="
            indice < acesos || (!tocando && !atual)
              ? 'opacity-100'
              : 'opacity-50'
          "
          :style="{ height: `${altura}px` }"
        />
      </span>
      <span
        class="shrink-0 rounded-full bg-white px-1.5 py-0.5 text-[13px] font-semibold leading-[18px] tabular-nums"
        :class="corDoDestaque"
      >
        {{ tempo }}
      </span>
    </div>
    <p
      v-if="transcricao && mostrarTranscricao"
      class="text-[15px] leading-5 whitespace-pre-wrap break-words"
    >
      {{ transcricao }}
    </p>
    <button
      v-else-if="transcricao"
      type="button"
      class="self-start p-0 text-[13px] leading-4 font-semibold"
      @click="mostrarTranscricao = true"
    >
      {{ t('CONVERSA_CANAL.INSTAGRAM.VER_TRANSCRICAO') }}
    </button>
    <audio
      ref="audio"
      :src="anexo.dataUrl"
      preload="metadata"
      class="hidden"
      @loadedmetadata="aoCarregar"
      @timeupdate="aoAndar"
      @play="tocando = true"
      @pause="tocando = false"
      @ended="aoAcabar"
    />
  </div>
</template>
