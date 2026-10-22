<script setup>
// Fotos e vídeos mandados juntos (#2079): grade de 3 colunas de 125 px, como no Direct
// (no celular estreito, encolhe junto). Só os cantos de fora do bloco ficam redondos; o resto, 4 px.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants';

const props = defineProps({
  anexos: { type: Array, required: true },
  cantos: { type: Object, required: true },
});

const { t } = useI18n();
const COLUNAS = 3;
const linhas = computed(() => Math.ceil(props.anexos.length / COLUNAS));
const ehVideo = anexo => anexo.fileType === ATTACHMENT_TYPES.VIDEO;

// O canto de fora de cada quadrado pega o canto do bloco (que segue o grupo).
const [emCimaEsq, emCimaDir, embaixoDir, embaixoEsq] = [0, 1, 2, 3];
const cantoDoBloco = indice =>
  String(props.cantos.borderRadius || '18px 18px 18px 18px').split(' ')[indice];
const cantosDoQuadrado = indice => {
  const linha = Math.floor(indice / COLUNAS);
  const coluna = indice % COLUNAS;
  const ultimaColuna =
    Math.min(COLUNAS, props.anexos.length - linha * COLUNAS) - 1;
  const canto = (fora, qual) => (fora ? cantoDoBloco(qual) : '4px');
  return {
    borderRadius: [
      canto(linha === 0 && coluna === 0, emCimaEsq),
      canto(linha === 0 && coluna === ultimaColuna, emCimaDir),
      canto(linha === linhas.value - 1 && coluna === ultimaColuna, embaixoDir),
      canto(linha === linhas.value - 1 && coluna === 0, embaixoEsq),
    ].join(' '),
  };
};
</script>

<template>
  <div class="grid w-[379px] max-w-full grid-cols-3 gap-0.5">
    <a
      v-for="(anexo, indice) in anexos"
      :key="anexo.id"
      :href="anexo.dataUrl"
      target="_blank"
      rel="noopener noreferrer"
      :aria-label="
        t(
          ehVideo(anexo)
            ? 'CONVERSA_CANAL.INSTAGRAM.ABRIR_VIDEO'
            : 'CONVERSA_CANAL.INSTAGRAM.ABRIR_FOTO'
        )
      "
      class="relative block aspect-square w-full overflow-hidden"
      :style="cantosDoQuadrado(indice)"
    >
      <video
        v-if="ehVideo(anexo)"
        :src="anexo.dataUrl"
        preload="metadata"
        muted
        playsinline
        class="size-full object-cover"
      />
      <img v-else :src="anexo.dataUrl" alt="" class="size-full object-cover" />
      <span
        v-if="ehVideo(anexo)"
        class="absolute inset-0 flex items-center justify-center pointer-events-none"
      >
        <span class="i-ph-play-fill size-8 text-white drop-shadow" />
      </span>
    </a>
  </div>
</template>
