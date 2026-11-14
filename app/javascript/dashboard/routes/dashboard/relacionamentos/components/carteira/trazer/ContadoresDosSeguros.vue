<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2897 — os números do topo do Conferir da planilha com seguros. Cada número
// vem com a palavra dele ("3 linhas precisam de você", "7 pessoas novas"):
// número sozinho não diz se conta seguros ou pessoas. Contador zerado não vem
// (carteira/segurosDaPlanilha.js). "Precisam de você" leva à lista das linhas.
// Em tela estreita são duas colunas, quantos forem os contadores: três
// espremem os rótulos longos a 390 px.
const props = defineProps({
  // `[{ chave, count }]`
  contadores: { type: Array, required: true },
});
const emit = defineEmits(['precisam']);

const { t } = useI18n();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.CONTADOR';
const QUE_LEVA_AS_LINHAS = 'PRECISAM';

const itens = computed(() =>
  props.contadores.map(({ chave, count }) => {
    const rotulo = t(`${BASE}.${chave}`, count);
    return {
      chave,
      count,
      rotulo,
      leitura: `${count} ${rotulo}`,
      levaAsLinhas: chave === QUE_LEVA_AS_LINHAS,
    };
  })
);
</script>

<template>
  <ul
    data-carteira="contadores-dos-seguros"
    aria-live="polite"
    :aria-label="t(`${BASE}.LISTA`)"
    class="grid grid-cols-2 p-0 m-0 list-none gap-x-6 gap-y-4 md:flex md:flex-wrap md:gap-x-10"
  >
    <li v-for="item in itens" :key="item.chave" :data-contador="item.chave">
      <component
        :is="item.levaAsLinhas ? 'button' : 'div'"
        :type="item.levaAsLinhas ? 'button' : undefined"
        class="flex flex-col items-start justify-start gap-1 p-0 m-0 bg-transparent border-0 min-h-11 text-start"
        :class="
          item.levaAsLinhas
            ? 'rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand'
            : ''
        "
        @click="item.levaAsLinhas ? emit('precisam') : undefined"
      >
        <span class="sr-only">{{ item.leitura }}</span>
        <span
          class="text-4xl font-bold leading-none tabular-nums text-n-slate-12"
          aria-hidden="true"
        >
          {{ item.count }}
        </span>
        <span
          class="text-sm text-n-slate-11"
          :class="
            item.levaAsLinhas
              ? 'underline underline-offset-4 decoration-n-weak'
              : ''
          "
          aria-hidden="true"
        >
          {{ item.rotulo }}
        </span>
      </component>
    </li>
  </ul>
</template>
