<script setup>
import { computed } from 'vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import GuideGrafico from './GuideGrafico.vue';
import { pedacosDaResposta } from './graficosNaResposta';

// A fala do Guia (#3184): o texto num cartão sem bico, com o ícone do Guia ao
// lado, e cada gráfico num cartão próprio na largura toda (#3158, B8a: no
// lugar do marcador que o modelo escreveu; o que ficou sem marcador vai para o
// fim, `pedacosDaResposta`).
//
// Sem bico e sem o nome em cima de cada fala: balão com bico é conversa com
// gente de verdade (a da cliente, no WhatsApp, fica ao lado). O nome continua
// para o leitor de tela.
const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  graficos: {
    type: Array,
    default: () => [],
  },
  senderName: {
    type: String,
    default: '',
  },
});

const pedacos = computed(() =>
  pedacosDaResposta(props.message?.content, props.graficos)
);

const formatar = texto => new MessageFormatter(texto).formattedMessage;
</script>

<template>
  <div class="flex items-start gap-2 w-full" data-resposta>
    <span
      class="grid place-content-center size-7 mt-1 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11"
      aria-hidden="true"
    >
      <span class="i-lucide-sparkles size-4" />
    </span>
    <div class="flex flex-col flex-1 gap-2 min-w-0 text-n-slate-12">
      <span class="sr-only">{{
        senderName || $t('AUTONOMIA_GUIDE.TITLE')
      }}</span>
      <p
        v-if="!message?.content"
        class="mb-0 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 text-base text-n-ruby-11"
        data-sem-texto
      >
        {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
      </p>
      <template v-for="(pedaco, indice) in pedacos" :key="indice">
        <GuideGrafico
          v-if="pedaco.tipo === 'grafico'"
          :modo="pedaco.grafico.modo"
          :titulo="pedaco.grafico.titulo"
          :medida="pedaco.grafico.medida"
          :barras="pedaco.grafico.barras"
          :de="pedaco.grafico.de"
          :ate="pedaco.grafico.ate"
        />
        <div
          v-else
          v-dompurify-html="formatar(pedaco.texto)"
          class="rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 text-base leading-relaxed break-words text-n-slate-12 [&_p]:mb-2 [&_p:last-child]:mb-0 [&_ul]:my-2 [&_ul]:ps-5 [&_ul]:list-disc [&_ol]:my-2 [&_ol]:ps-5 [&_ol]:list-decimal [&_a]:text-n-blue-11 [&_a]:underline"
          data-trecho
        />
      </template>
    </div>
  </div>
</template>
