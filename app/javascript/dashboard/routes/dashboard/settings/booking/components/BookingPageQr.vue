<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';

// QR code do link público, gerado no navegador (mesmo pacote dos links
// rastreados). Fundo branco fixo: o QR precisa de contraste para a câmera.
const props = defineProps({ url: { type: String, required: true } });
const { t } = useI18n();
const image = ref('');
const failed = ref(false);
const QR_SIZE = 512;

watch(
  () => props.url,
  async (url, _previous, onCleanup) => {
    let canceled = false;
    onCleanup(() => {
      canceled = true;
    });
    image.value = '';
    failed.value = false;
    try {
      const dataUrl = await QRCode.toDataURL(url, { width: QR_SIZE });
      if (!canceled) image.value = dataUrl;
    } catch {
      if (!canceled) failed.value = true;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    data-qr
    class="flex items-center justify-center p-3 bg-white rounded-xl size-48 ring-1 ring-inset ring-n-weak"
  >
    <img
      v-if="image"
      :src="image"
      :alt="t('BOOKING.LINK.QR_ALT')"
      class="size-full object-contain"
    />
    <p v-else-if="failed" role="alert" class="m-0 text-sm text-slate-700">
      {{ t('BOOKING.LINK.QR_ERROR') }}
    </p>
    <span
      v-else
      class="i-lucide-loader-circle size-5 animate-spin text-slate-700"
      aria-hidden="true"
    />
  </div>
</template>
