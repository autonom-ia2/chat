<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import WhatsAppButton from './WhatsAppButton.vue';

// Recado de ação que não deu certo na gestão da reunião: um único alerta por tela e a saída pelo WhatsApp da
// empresa (RA-17).
const { manage } = useFlow();
const { t } = useI18n();
</script>

<template>
  <div class="contents">
    <div v-if="manage.error.value" class="flex flex-col gap-3">
      <p
        role="alert"
        class="rounded-xl bg-red-50 p-4 text-base font-medium text-red-900"
      >
        {{ t(manage.error.value) }}
      </p>
      <WhatsAppButton :url="manage.whatsappUrl.value" />
    </div>
  </div>
</template>
