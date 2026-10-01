<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';

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
      // Always use the tracked URL: wa.me bypasses click attribution.
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
  <div class="flex items-center justify-center p-4 bg-white rounded-xl">
    <img
      v-if="image"
      :src="image"
      :alt="t('CRM_KANBAN.TRACKED_LINKS.PAGE.QR_ALT')"
      class="size-full object-contain"
    />
    <p v-else-if="failed" role="alert" class="m-0 text-xs text-slate-700">
      {{ t('CRM_KANBAN.TRACKED_LINKS.PAGE.QR_ERROR') }}
    </p>
    <span
      v-else
      class="i-lucide-loader-circle size-5 animate-spin text-slate-700"
    />
  </div>
</template>
