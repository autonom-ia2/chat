<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// chat#1487 — pausar o WhatsApp API sem desvincular o aparelho. Pede confirmação curta dizendo o efeito.
defineProps({
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm']);

const { t } = useI18n();
const dialogRef = ref(null);

const confirm = () => {
  emit('confirm');
  dialogRef.value?.close();
};
</script>

<template>
  <NextButton
    :is-loading="isBusy"
    color="slate"
    variant="outline"
    size="sm"
    icon="i-lucide-pause"
    :label="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.BUTTON')"
    @click="dialogRef?.open()"
  />
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM_TITLE')"
    :description="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM_TEXT')"
    :confirm-button-label="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CONFIRM')"
    :cancel-button-label="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.CANCEL')"
    @confirm="confirm"
  />
</template>
