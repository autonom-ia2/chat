<script setup>
// Selo de reações do WhatsApp (#1702): redondo, com o emoji, encostado embaixo do
// balão reagido e meio para fora dele, como no app. Mais de uma reação: até 3 emojis
// diferentes e o total. O balão reserva o espaço de baixo (Base.vue).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ORIENTATION } from '../message/constants';
import { EMOJIS_NO_SELO, agruparReacoes, descreverReacoes } from './reacoes';

const props = defineProps({
  reacoes: { type: Array, required: true },
  lado: { type: String, default: ORIENTATION.LEFT },
  nomeDoCliente: { type: String, default: '' },
});

const { t } = useI18n();

const grupos = computed(() =>
  agruparReacoes(props.reacoes).slice(0, EMOJIS_NO_SELO)
);
const total = computed(() => props.reacoes.length);
const rotulo = computed(() =>
  descreverReacoes(props.reacoes, { t, nomeDoCliente: props.nomeDoCliente })
);
</script>

<template>
  <span
    role="img"
    :aria-label="rotulo"
    :title="rotulo"
    class="absolute -bottom-[18px] z-[3] inline-flex items-center gap-0.5 h-[26px] px-1.5 rounded-full bg-white dark:bg-[#242626] border-2 border-[#F4F1EC] dark:border-[#161717] shadow-[0_1px_1px_rgba(11,20,26,0.13)] select-none"
    :class="
      lado === ORIENTATION.RIGHT
        ? 'ltr:right-2 rtl:left-2'
        : 'ltr:left-2 rtl:right-2'
    "
    data-selo-de-reacoes
  >
    <span
      v-for="grupo in grupos"
      :key="grupo.emoji"
      aria-hidden="true"
      class="text-[14px] leading-none"
    >
      {{ grupo.emoji }}
    </span>
    <span
      v-if="total > 1"
      aria-hidden="true"
      class="ps-0.5 text-[12px] leading-none text-[#666666] dark:text-[#A7A8A8]"
    >
      {{ total }}
    </span>
  </span>
</template>
