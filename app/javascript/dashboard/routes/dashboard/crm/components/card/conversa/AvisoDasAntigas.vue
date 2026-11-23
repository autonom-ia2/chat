<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #3165 — as mensagens antigas não vieram: diz e deixa tentar de novo.
defineEmits(['tentar']);
const { t } = useI18n();
</script>

<template>
  <li class="flex list-none flex-col items-center gap-2 py-3 text-center">
    <span class="text-sm text-n-slate-11">
      {{ t('CRM_CARD.CONVERSAS.VISOR.ERRO_ANTIGAS') }}
    </span>
    <Button
      :label="t('CRM_CARD.CONVERSAS.VISOR.TENTAR_DE_NOVO')"
      icon="i-lucide-refresh-cw"
      slate
      faded
      class="!min-h-11"
      @click="$emit('tentar')"
    />
  </li>
</template>
