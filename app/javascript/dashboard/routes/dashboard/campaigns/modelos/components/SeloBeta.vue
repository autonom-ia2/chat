<script setup>
// Selo "Beta" dos produtos do catálogo (#1418): validado só com catálogo
// simulado, então avisa que é recurso novo e para onde ir se algo falhar.
// `comAviso` mostra também a linha curta do suporte.
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';

defineProps({
  comAviso: { type: Boolean, default: false },
});

const { t } = useI18n();
</script>

<template>
  <span v-if="!comAviso" class="inline-flex" data-selo-beta>
    <Label :label="t('MODELOS_WHATSAPP.BETA.SELO')" color="blue" compact />
  </span>
  <p
    v-else
    class="flex flex-wrap items-center gap-2 m-0 text-xs text-n-slate-11"
    data-selo-beta
  >
    <Label :label="t('MODELOS_WHATSAPP.BETA.SELO')" color="blue" compact />
    {{ t('MODELOS_WHATSAPP.BETA.AVISO') }}
  </p>
</template>
