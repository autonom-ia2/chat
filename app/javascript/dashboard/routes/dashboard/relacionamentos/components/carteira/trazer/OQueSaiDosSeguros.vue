<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2897 — o que o Desfazer de uma leva de seguros tira, dito ANTES: os
// seguros (com os PDFs), as pessoas que continuam, os cards de renovação que
// saem do funil e as propostas já enviadas, que não voltam. Linha zerada some.
const props = defineProps({
  previa: { type: Object, required: true },
});

const { t } = useI18n();
const td = (chave, quantos) =>
  t(
    `RELACIONAMENTOS_CARTEIRA.TRAZER.DESFAZER.${chave}`,
    { count: quantos },
    quantos
  );

const frases = computed(() => {
  const { origem, seguros, pessoas, cards, propostas } = props.previa;
  return [
    [`TIRA.${origem.toUpperCase()}`, seguros],
    ['PESSOAS_FICAM', pessoas],
    ['CARDS', cards],
    ['PROPOSTAS', propostas],
  ]
    .filter(([, quantos]) => quantos > 0)
    .map(([chave, quantos]) => ({ chave, texto: td(chave, quantos) }));
});
</script>

<template>
  <div data-carteira="o-que-sai" class="flex flex-col gap-3">
    <p
      v-for="(frase, posicao) in frases"
      :key="frase.chave"
      class="m-0"
      :class="{ 'text-n-slate-12': posicao === 0 }"
    >
      {{ frase.texto }}
    </p>
  </div>
</template>
