<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';

// #2556 — o gatilho de data deixou de fora os cards ou contatos cujo campo tem
// a data escrita em outro formato. O servidor manda só quantos, de quem e o
// nome do campo, nunca o valor; sem nenhum, não vem nada e o aviso some.
const props = defineProps({
  aviso: { type: Object, default: null },
});

const { t } = useI18n();

const frase = computed(() => {
  const quantos = props.aviso?.quantos || 0;
  if (!quantos) return '';
  const chave = props.aviso.alvo === 'card' ? 'CARDS' : 'CONTATOS';
  return t(
    `AUTOMACAO_LIVRE.EDITOR.DATAS_INVALIDAS.${chave}`,
    { n: quantos, campo: props.aviso.campo },
    quantos
  );
});
</script>

<template>
  <Banner v-if="frase" data-datas-invalidas role="status" color="amber">
    {{ frase }}
  </Banner>
</template>
