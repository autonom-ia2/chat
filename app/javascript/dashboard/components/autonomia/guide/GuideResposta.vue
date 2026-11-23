<script setup>
import { computed } from 'vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import CopilotAssistantMessage from 'dashboard/components-next/copilot/CopilotAssistantMessage.vue';
import GuideGrafico from './GuideGrafico.vue';
import { pedacosDaResposta } from './graficosNaResposta';

// #3158 (B8a) — a fala do Guia no balão. Sem gráfico, é a mensagem de sempre.
// Com gráfico, cada um entra no lugar do marcador que o modelo escreveu; o que
// ficou sem marcador vai para o fim (`pedacosDaResposta`).
const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  graficos: {
    type: Array,
    default: () => [],
  },
  isLastMessage: {
    type: Boolean,
    default: false,
  },
  senderName: {
    type: String,
    default: '',
  },
});

const temGraficos = computed(() => (props.graficos || []).length > 0);

const pedacos = computed(() =>
  pedacosDaResposta(props.message?.content, props.graficos)
);

const formatar = texto => new MessageFormatter(texto).formattedMessage;
</script>

<template>
  <CopilotAssistantMessage
    v-if="!temGraficos"
    :message="message"
    :is-last-message="isLastMessage"
    :sender-name="senderName"
  />
  <div
    v-else
    class="flex flex-col gap-1 text-n-slate-12"
    data-resposta-com-graficos
  >
    <!-- Mesma cara do CopilotAssistantMessage: nome e, na resposta retida (sem texto), o mesmo aviso acima do gráfico. -->
    <div class="font-medium">
      {{ senderName || $t('AUTONOMIA_GUIDE.TITLE') }}
    </div>
    <span v-if="!message?.content" class="text-n-ruby-11" data-sem-texto>
      {{ $t('CAPTAIN.COPILOT.EMPTY_MESSAGE') }}
    </span>
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
        class="prose-sm break-words"
        data-trecho
      />
    </template>
  </div>
</template>
