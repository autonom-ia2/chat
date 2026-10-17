<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1487 — desconectar tira o aparelho do celular e exige QR novo para voltar: confirma antes e lembra que
// "Pausar" existe para parar só por um tempo.
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
    data-disconnect
    :is-loading="isBusy"
    color="ruby"
    variant="ghost"
    icon="i-lucide-unplug"
    class="min-h-11"
    :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.DISCONNECT')"
    @click="dialogRef?.open()"
  />
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="$t('INBOX_MGMT.WHATSAPP_HYBRID.DISCONNECT_CONFIRM.TITLE')"
    :description="$t('INBOX_MGMT.WHATSAPP_HYBRID.DISCONNECT_CONFIRM.TEXT')"
    :confirm-button-label="
      $t('INBOX_MGMT.WHATSAPP_HYBRID.DISCONNECT_CONFIRM.CONFIRM')
    "
    :cancel-button-label="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CANCEL')"
    @confirm="confirm"
  />
</template>
