<script setup>
import { useI18n } from 'vue-i18n';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { chaveDoSelo, tomDoSelo } from '../../carteira/tomDoSelo';

// #2897 — um selo da carteira pelo nome dele (ativo, em_renovacao, vencido…): a
// cor e o texto saem de uma regra só. A marca do robô de print vem de quem usa.
defineProps({
  selo: { type: String, required: true },
});

const { t } = useI18n();
</script>

<template>
  <SeloDeEstado :tom="tomDoSelo(selo)" :data-selo-da-carteira="selo">
    {{ t(chaveDoSelo(selo)) }}
  </SeloDeEstado>
</template>
