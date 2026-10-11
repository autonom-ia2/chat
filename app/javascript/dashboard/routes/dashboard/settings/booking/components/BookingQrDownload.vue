<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { QR_FORMATS, qrFileName, saveBlobUrl } from '../bookingQrFile';

// Baixar o QR code (#1290): PNG de impressão e, discreto, SVG para a gráfica.
// O arquivo nasce no navegador. Navegador que bloqueia download costuma não
// avisar, então depois de cada pedido fica um link para abrir a imagem e
// salvar por lá, com o texto certo para quando o bloqueio é sabido.
const props = defineProps({
  url: { type: String, required: true },
  // Nome da página (e da pessoa, no link por pessoa): vira o nome do arquivo.
  name: { type: String, default: '' },
});

const { t } = useI18n();
const busy = ref('');
// O último arquivo gerado: { url, file, accepted }.
const last = ref(null);
// Muda quando o pedido em andamento deixa de valer (outro link ou saída).
let round = 0;

const files = computed(() => ({
  png: qrFileName(props.name, QR_FORMATS.png.extension),
  svg: qrFileName(props.name, QR_FORMATS.svg.extension),
}));

const reset = () => {
  round += 1;
  if (last.value) URL.revokeObjectURL(last.value.url);
  last.value = null;
};

const download = async format => {
  if (busy.value) return;
  reset();
  const current = round;
  const file = files.value[format];
  busy.value = format;
  try {
    const blob = await QR_FORMATS[format].build(props.url);
    if (current !== round) return;
    const url = URL.createObjectURL(blob);
    const accepted = saveBlobUrl(url, file);
    last.value = { url, file, accepted };
    if (accepted) useAlert(t('BOOKING.LINK.QR_DOWNLOADING', { file }));
  } catch {
    if (current === round) useAlert(t('BOOKING.LINK.QR_DOWNLOAD_ERROR'));
  } finally {
    busy.value = '';
  }
};

watch(() => [props.url, props.name], reset);
onBeforeUnmount(reset);
</script>

<template>
  <div data-qr-download class="flex flex-col">
    <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
      <button
        type="button"
        data-qr-download-png
        :aria-disabled="busy ? 'true' : undefined"
        :aria-busy="busy === 'png' ? 'true' : undefined"
        :aria-label="t('BOOKING.LINK.QR_DOWNLOAD_LABEL', { file: files.png })"
        class="inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand aria-disabled:opacity-60 aria-disabled:cursor-not-allowed"
        @click="download('png')"
      >
        <span class="i-lucide-download size-4" aria-hidden="true" />
        {{ t('BOOKING.LINK.QR_DOWNLOAD') }}
      </button>
      <button
        type="button"
        data-qr-download-svg
        :aria-disabled="busy ? 'true' : undefined"
        :aria-busy="busy === 'svg' ? 'true' : undefined"
        :aria-label="
          t('BOOKING.LINK.QR_DOWNLOAD_SVG_LABEL', { file: files.svg })
        "
        class="inline-flex items-center min-h-11 px-1 rounded-lg text-sm font-medium underline text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand aria-disabled:opacity-60 aria-disabled:cursor-not-allowed"
        @click="download('svg')"
      >
        {{ t('BOOKING.LINK.QR_DOWNLOAD_SVG') }}
      </button>
    </div>
    <div role="status" data-qr-download-status>
      <p
        v-if="last"
        :data-qr-download-accepted="last.accepted ? 'true' : 'false'"
        class="flex flex-wrap items-center gap-x-2 m-0 mt-2 text-base text-n-slate-11"
      >
        {{
          last.accepted
            ? t('BOOKING.LINK.QR_DOWNLOAD_RETRY')
            : t('BOOKING.LINK.QR_DOWNLOAD_BLOCKED')
        }}
        <a
          data-qr-download-open
          :href="last.url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center min-h-11 font-semibold underline break-all text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ t('BOOKING.LINK.QR_DOWNLOAD_OPEN', { file: last.file }) }}
        </a>
      </p>
    </div>
  </div>
</template>
