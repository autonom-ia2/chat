<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import BookingPageQr from './BookingPageQr.vue';

// Copiar link, QR code e Abrir: o que a pessoa faz com o link pronto. Não
// muda nada na página, então quem só vê também usa.
defineProps({ url: { type: String, required: true } });

const { t } = useI18n();
const showQr = ref(false);

const BUTTON =
  'inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';

const copy = async url => {
  try {
    await copyTextToClipboard(url);
    useAlert(t('BOOKING.LINK.COPIED'));
  } catch {
    useAlert(t('BOOKING.LINK.COPY_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <p
      class="m-0 text-base font-medium break-all text-n-slate-12"
      data-link-url
    >
      {{ url }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button type="button" data-copy :class="BUTTON" @click="copy(url)">
        <span class="i-lucide-copy size-4" aria-hidden="true" />
        {{ t('BOOKING.LINK.COPY') }}
      </button>
      <button
        type="button"
        data-qr-toggle
        :class="BUTTON"
        :aria-expanded="showQr ? 'true' : 'false'"
        @click="showQr = !showQr"
      >
        <span class="i-lucide-qr-code size-4" aria-hidden="true" />
        {{ showQr ? t('BOOKING.LINK.QR_HIDE') : t('BOOKING.LINK.QR') }}
      </button>
      <a
        data-open
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
        :class="BUTTON"
        :aria-label="t('BOOKING.LINK.OPEN_LABEL')"
      >
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        {{ t('BOOKING.LINK.OPEN') }}
      </a>
    </div>
    <BookingPageQr v-if="showQr" :url="url" />
  </div>
</template>
