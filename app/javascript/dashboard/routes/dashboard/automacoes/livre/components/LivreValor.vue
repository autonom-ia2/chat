<script setup>
import { useI18n } from 'vue-i18n';
import { rotuloDaVariavel } from '../prototipo/frases';

// #2414 F0 — texto com variáveis. No editor cada variável é um chip com o nome
// ("Nome do contato"); no ensaio, com `valores`, vira o valor de exemplo.
defineProps({
  pedacos: { type: Array, default: () => [] },
  valores: { type: Object, default: null },
});

const { t } = useI18n();
</script>

<template>
  <span class="whitespace-pre-line break-words">
    <template v-for="(pedaco, indice) in pedacos" :key="indice">
      <template v-if="typeof pedaco === 'string'">{{ pedaco }}</template>
      <template v-else-if="valores && valores[pedaco.$valor]">
        {{ valores[pedaco.$valor] }}
      </template>
      <span
        v-else
        data-variavel
        class="inline-flex items-center gap-1 px-1.5 mx-0.5 text-[0.8125rem] font-medium align-baseline rounded-md bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-braces size-3" aria-hidden="true" />
        {{ rotuloDaVariavel(pedaco.$valor, t) }}
      </span>
    </template>
  </span>
</template>
