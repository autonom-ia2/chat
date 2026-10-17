<script setup>
// Etiqueta do dia no meio da conversa (#1702): "Hoje", "Ontem", o dia da semana ou a
// data, no fuso da conta, como no WhatsApp.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFuso } from './pele';
import { useAgora } from './useAgora';
import { idiomaDoPainel, rotuloDoDia } from './dataDaConversa';
import { CLASSES_DO_SEPARADOR_DE_DIA } from './visualWhatsapp';

const props = defineProps({
  quando: { type: Number, required: true },
});

const { t, locale } = useI18n();
const fuso = useFuso();
// Passando da meia-noite com a conversa aberta, "Hoje" vira "Ontem".
const agora = useAgora();

const rotulo = computed(() =>
  rotuloDoDia({
    quando: props.quando,
    agora: agora.value,
    fuso: fuso.value,
    t,
    idioma: idiomaDoPainel(locale.value),
  })
);
</script>

<template>
  <li class="flex justify-center list-none my-3" data-separador-de-dia>
    <span :class="CLASSES_DO_SEPARADOR_DE_DIA">{{ rotulo }}</span>
  </li>
</template>
