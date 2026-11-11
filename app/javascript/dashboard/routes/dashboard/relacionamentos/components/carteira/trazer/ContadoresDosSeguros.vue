<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2897 — os contadores do topo da conferência de seguros ("164 prontos · 4
// precisam de você · 120 pessoas já estavam aqui"). O de "precisam de você" é
// um botão que leva ao bloco dos problemas. Região viva: os números mudam a
// cada problema resolvido.
const props = defineProps({
  // [{ chave, count }], já sem os zerados (carteira/contagemDeSeguros.js).
  contadores: { type: Array, required: true },
});
const emit = defineEmits(['precisam']);

const { t } = useI18n();
const tc = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.CONFERIR.${chave}`, ...resto);

const PRECISAM = 'PRECISAM';

const itens = computed(() =>
  props.contadores.map(({ chave, count }) => {
    const rotulo = tc(`CONTADOR.${chave}`, count);
    return {
      chave,
      count,
      rotulo,
      leitura: `${count} ${rotulo}`,
      levaAosProblemas: chave === PRECISAM,
    };
  })
);
</script>

<template>
  <ul
    data-carteira="contadores"
    aria-live="polite"
    :aria-label="tc('CONTADORES')"
    class="grid grid-cols-2 p-0 m-0 list-none gap-x-6 gap-y-4 md:flex md:flex-wrap md:gap-x-10"
  >
    <li v-for="item in itens" :key="item.chave" :data-contador="item.chave">
      <component
        :is="item.levaAosProblemas ? 'button' : 'div'"
        :type="item.levaAosProblemas ? 'button' : undefined"
        class="flex flex-col items-start justify-start gap-1 p-0 m-0 bg-transparent border-0 min-h-11 text-start"
        :class="
          item.levaAosProblemas
            ? 'rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand'
            : ''
        "
        @click="item.levaAosProblemas ? emit('precisam') : undefined"
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
            item.levaAosProblemas
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
