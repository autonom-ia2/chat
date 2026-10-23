<script setup>
// Mensagem de voz do Direct (#2079): play redondo, a onda de barras que acende
// enquanto toca e a pílula branca com o tempo. Na enviada, ícone e tempo em azul.
// Embaixo, "Ver transcrição" quando o áudio já tem o texto transcrito.
// A onda é a do próprio som (#2113), calculada do arquivo como no WhatsApp
// (carregarOnda), quando o balão aparece na tela. Enquanto ela não chega, ou se o
// navegador não conseguir ler o arquivo, ficam barras de reserva com alturas fixas
// por anexo, para cada áudio ter a sua e ela não mudar a cada tela. O áudio enviado
// é o nosso arquivo; o recebido ainda vem com o endereço da Meta (data_url do anexo)
// até a plataforma guardar a mídia recebida, e se ele não puder ser lido fica a reserva.
import { computed, onBeforeUnmount, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import {
  BARRAS as BARRAS_DO_ARQUIVO,
  NIVEIS,
  carregarOnda,
} from '../audio/ondaDoAudio';
import { ENVIADO, RECEBIDO } from './visualInstagram';

const props = defineProps({
  anexo: { type: Object, required: true },
  enviada: { type: Boolean, default: false },
  cantos: { type: Object, required: true },
});

const { t } = useI18n();
const BARRAS = 32;
// Uma altura por nível da onda (0 a NIVEIS - 1), de 3 a 26 px: o silêncio ainda aparece.
const ALTURAS = [
  'h-[3px]',
  'h-[5px]',
  'h-[7px]',
  'h-[9px]',
  'h-[11px]',
  'h-[13px]',
  'h-[15px]',
  'h-[17px]',
  'h-[19px]',
  'h-[21px]',
  'h-[23px]',
  'h-[26px]',
];
// Reserva: gerador simples com semente no id do anexo, mesma onda sempre para o mesmo áudio.
const reservaDoAnexo = id => {
  let semente = Number(id) || 1;
  return Array.from({ length: BARRAS }, () => {
    semente = (semente * 9301 + 49297) % 233280;
    const sorteio = semente / 233280;
    return Math.round(sorteio * sorteio * (NIVEIS - 1));
  });
};
// A onda do arquivo vem em BARRAS_DO_ARQUIVO; o balão do Direct desenha BARRAS.
const nasBarrasDoDirect = barras =>
  Array.from(
    { length: BARRAS },
    (_, i) => barras[Math.floor((i * BARRAS_DO_ARQUIVO) / BARRAS)] ?? 0
  );

const raiz = useTemplateRef('raiz');
const barrasDoArquivo = ref(null);
const onda = computed(() =>
  (barrasDoArquivo.value || reservaDoAnexo(props.anexo.id)).map(
    nivel => ALTURAS[nivel] || ALTURAS[0]
  )
);
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
  if (Number.isFinite(total)) duracao.value = total;
};

// A onda: uma vez, quando o balão aparece na tela. O endereço ganha o carimbo de
// tempo (como no WhatsApp) para o download não reaproveitar a cópia que o <audio>
// guardou sem a permissão de leitura; endereço que nem é URL fica na reserva. A onda
// fica guardada pelo endereço sem o carimbo: voltar à conversa não baixa de novo.
const enderecoDaOnda = () => {
  if (!props.anexo.dataUrl) return null;
  try {
    return timeStampAppendedURL(props.anexo.dataUrl);
  } catch {
    return null;
  }
};
const cancelar = new AbortController();
const pedirOnda = async () => {
  const endereco = enderecoDaOnda();
  if (!endereco) return;
  const resultado = await carregarOnda(endereco, {
    signal: cancelar.signal,
    chave: props.anexo.dataUrl,
  });
  if (!resultado?.barras?.length) return;
  barrasDoArquivo.value = nasBarrasDoDirect(resultado.barras);
  if (!duracao.value && Number.isFinite(resultado.duracao)) {
    duracao.value = resultado.duracao;
  }
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
    ref="raiz"
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
          :class="[
            altura,
            indice < acesos || (!tocando && !atual)
              ? 'opacity-100'
              : 'opacity-50',
          ]"
          data-barra-da-voz
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
