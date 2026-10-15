<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1487 — pausar o WhatsApp API sem desvincular o aparelho. Pede confirmação curta dizendo o efeito, com o botão
// normal (azul): pausar é reversível. Só Desconectar usa o vermelho de ação perigosa.
defineProps({
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm']);

const dialogRef = ref(null);

const confirm = () => {
  emit('confirm');
  dialogRef.value?.close();
};
</script>

<template>
  <Button
    data-pause
    :is-loading="isBusy"
    color="slate"
    variant="outline"
    icon="i-lucide-pause"
    class="min-h-11"
    :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.BUTTON')"
    @click="dialogRef?.open()"
  />
  <Dialog
    ref="dialogRef"
    :title="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM_TITLE')"
    :description="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM_TEXT')"
    :confirm-button-label="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM')"
    :cancel-button-label="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CANCEL')"
    @confirm="confirm"
  />
</template>
