<script setup>
// O selo de reações do Direct (#2113): emoji pequeno numa pílula encostada no canto de
// baixo do balão (à esquerda na recebida, à direita na nossa), com a borda na cor do
// fundo. Mais de uma reação: até 3 emojis diferentes e o total. A linha reserva o
// espaço de baixo (LinhaDoInstagram).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { EMOJIS_NO_SELO, agruparReacoes, descreverReacoes } from '../reacoes';
import { useInstagramDaConversa } from './useConversaDoInstagram';
import { PILULA_DE_REACAO, SECUNDARIO } from './visualInstagram';

const props = defineProps({
  reacoes: { type: Array, required: true },
  enviada: { type: Boolean, default: false },
});

const { t } = useI18n();
const { contato } = useInstagramDaConversa();

const grupos = computed(() =>
  agruparReacoes(props.reacoes).slice(0, EMOJIS_NO_SELO)
);
const total = computed(() => props.reacoes.length);
const rotulo = computed(() =>
  descreverReacoes(props.reacoes, {
    t,
    nomeDoCliente: contato.value?.name || '',
  })
);
</script>

<template>
  <span
    role="img"
    :aria-label="rotulo"
    :title="rotulo"
    class="absolute bottom-0 z-[3] inline-flex h-6 items-center gap-0.5 rounded-full px-1.5 select-none"
    :class="[PILULA_DE_REACAO, enviada ? 'end-2' : 'start-2']"
    data-reacoes-do-instagram
  >
    <span
      v-for="grupo in grupos"
      :key="grupo.emoji"
      aria-hidden="true"
      class="text-[13px] leading-none"
    >
      {{ grupo.emoji }}
    </span>
    <span
      v-if="total > 1"
      aria-hidden="true"
      class="ps-0.5 text-[12px] leading-none"
      :class="SECUNDARIO"
    >
      {{ total }}
    </span>
  </span>
</template>
