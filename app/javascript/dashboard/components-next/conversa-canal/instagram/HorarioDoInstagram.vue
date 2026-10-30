<script setup>
// Horário entre os blocos da conversa (#2079): centralizado, 12 px, cinza, no fuso da
// conta ("12:41", "10 de out de 2026 06:58", "04/07/2025 16:29").
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAgora } from '../useAgora';
import { idiomaDoPainel } from '../dataDaConversa';
import { useInstagramDaConversa } from './useConversaDoInstagram';
import { horarioDoInstagram } from './sequenciaDoInstagram';
import { HORARIO } from './visualInstagram';

const props = defineProps({
  quando: { type: Number, required: true },
});

const { t, locale } = useI18n();
const { fuso } = useInstagramDaConversa();
const agora = useAgora();
const texto = computed(() =>
  horarioDoInstagram({
    quando: props.quando,
    agora: agora.value,
    fuso: fuso.value,
    t,
    idioma: idiomaDoPainel(locale.value),
  })
);
</script>

<template>
  <li class="flex justify-center list-none pt-4 pb-3">
    <span :class="HORARIO">{{ texto }}</span>
  </li>
</template>
