<script setup>
import { useI18n } from 'vue-i18n';
import MessageScreen from './MessageScreen.vue';

// Link inexistente, vencido ou cancelado (J1-A6): recado simples, sem expor nenhum dado.
const { t } = useI18n();
</script>

<template>
  <MessageScreen
    icon="i-lucide-link-2-off"
    :title="t('BOOKING_V2.NOT_FOUND.TITLE')"
    :body="t('BOOKING_V2.NOT_FOUND.BODY')"
  />
</template>
