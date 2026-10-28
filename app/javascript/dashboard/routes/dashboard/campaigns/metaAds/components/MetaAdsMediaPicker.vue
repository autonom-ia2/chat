<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  MEDIA_ACCEPT,
  formatoDaMidia,
  lerMidia,
  soltarMidia,
} from '../midiaDoAnuncio';
import { enviarMidia } from '../criacaoNaMeta';

// Anúncios da Meta (#2198), criar: a foto ou o vídeo do anúncio. O caminho principal é mandar do celular (tocar ou
// arrastar); as imagens que a conta já usou em anúncios ficam como segunda opção, para quem já anunciou. O arquivo
// sobe para a Meta assim que a pessoa escolhe (a tela mostra que está enviando); só depois vira a mídia do anúncio.
// Valor: { kind: 'image' | 'video', url, poster, width, height, duration, source: 'upload' | 'library', hash,
// video_id, image_hash, file_name } ou null. `poster`: a capa do vídeo, tirada do primeiro quadro no navegador.
const props = defineProps({
  // Imagens já usadas na conta de anúncios: [{ hash, url, width, height }].
  library: { type: Array, default: () => [] },
});

// `uploading`: enquanto sobe, o "Continuar" espera.
const emit = defineEmits(['uploading']);

const media = defineModel({ type: Object, default: null });

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.MEDIA';
const input = ref(null);
const dragging = ref(false);
const error = ref('');
const showLibrary = ref(false);
const uploading = ref(false);
// Só a última escolha vale: trocar de arquivo no meio do envio descarta o anterior.
let attempt = 0;

const accept = MEDIA_ACCEPT;

const setUploading = value => {
  uploading.value = value;
  emit('uploading', value);
};

const take = async file => {
  error.value = '';
  if (!file) return;
  attempt += 1;
  const mine = attempt;
  let chosen = null;
  try {
    chosen = await lerMidia(file);
  } catch (refused) {
    error.value = t(`${KEY}.ERRORS.${refused.code || 'READ'}`, {
      max: refused.max,
    });
    return;
  }
  setUploading(true);
  try {
    const sent = await enviarMidia(chosen, file);
    if (mine !== attempt) {
      soltarMidia(chosen);
      return;
    }
    soltarMidia(media.value);
    media.value = sent;
  } catch {
    soltarMidia(chosen);
    if (mine === attempt) error.value = t(`${KEY}.ERRORS.UPLOAD`);
  } finally {
    if (mine === attempt) setUploading(false);
  }
};

// O campo volta a ficar vazio: escolher o mesmo arquivo de novo também chega aqui.
const choose = event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  take(file);
};
const drop = event => {
  dragging.value = false;
  take(event.dataTransfer?.files?.[0]);
};
const pick = () => input.value?.click();

// Imagem da biblioteca já está na conta de anúncios: tem `hash` e não sobe nada.
const useLibrary = image => {
  attempt += 1;
  if (uploading.value) setUploading(false);
  error.value = '';
  soltarMidia(media.value);
  media.value = { kind: 'image', ...image, source: 'library' };
};

// Saiu da tela no meio do envio: o resultado não volta mais, e o "Continuar" não fica esperando.
onBeforeUnmount(() => {
  attempt += 1;
  if (uploading.value) emit('uploading', false);
});

const shape = computed(() => (media.value ? formatoDaMidia(media.value) : ''));
const duration = computed(() =>
  media.value?.kind === 'video' ? Math.round(media.value.duration || 0) : 0
);

const chosenLabel = computed(() =>
  media.value.kind === 'video'
    ? t(`${KEY}.CHOSEN_VIDEO`, { seconds: duration.value })
    : t(`${KEY}.CHOSEN_IMAGE`)
);
</script>

<template>
  <div data-create-media class="flex min-w-0 flex-col gap-3">
    <span class="text-sm font-medium text-n-slate-12">
      {{ $t(`${KEY}.LABEL`) }}
    </span>
    <input
      ref="input"
      type="file"
      class="hidden"
      data-create-media-input
      :accept="accept"
      @change="choose"
    />

    <p
      v-if="uploading"
      data-create-media-uploading
      role="status"
      class="m-0 flex min-h-11 items-center gap-3 rounded-2xl bg-n-alpha-1 px-4 text-sm text-n-slate-12"
    >
      <Spinner :size="20" class="shrink-0 text-n-brand" />
      {{ $t(`${KEY}.UPLOADING`) }}
    </p>

    <div
      v-else-if="media"
      data-create-media-chosen
      class="flex min-w-0 flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl bg-n-alpha-1 p-3"
    >
      <div
        class="relative size-20 shrink-0 overflow-hidden rounded-xl bg-n-alpha-2"
      >
        <video
          v-if="media.kind === 'video' && !media.poster"
          :src="media.url"
          muted
          playsinline
          preload="metadata"
          class="size-full object-cover"
        />
        <img
          v-else
          :src="media.poster || media.url"
          alt=""
          class="size-full object-cover"
        />
        <span
          v-if="media.kind === 'video'"
          class="absolute inset-0 flex items-center justify-center"
          aria-hidden="true"
        >
          <span class="i-lucide-circle-play size-8 text-white drop-shadow" />
        </span>
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ chosenLabel }}
        </span>
        <span data-create-media-shape class="text-xs text-n-slate-11">
          {{ $t(`${KEY}.SHAPES.${shape}`) }}
        </span>
      </div>
      <button
        type="button"
        data-create-media-change
        class="inline-flex min-h-11 shrink-0 basis-full items-center gap-2 rounded-lg border-0 bg-transparent px-3 text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand sm:basis-auto"
        @click="pick"
      >
        <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
        {{ $t(`${KEY}.CHANGE`) }}
      </button>
    </div>

    <button
      v-else
      type="button"
      data-create-media-drop
      class="flex min-h-40 w-full flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed px-6 py-8 text-center transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        dragging
          ? 'border-n-brand bg-n-brand/10'
          : 'border-n-strong bg-n-alpha-1 hover:border-n-brand'
      "
      @click="pick"
      @dragover.prevent="dragging = true"
      @dragleave="dragging = false"
      @drop.prevent="drop"
    >
      <span
        class="i-lucide-image-plus size-8 text-n-brand"
        aria-hidden="true"
      />
      <span class="text-base font-semibold text-n-slate-12">
        {{ $t(`${KEY}.DROP`) }}
      </span>
      <span class="max-w-sm text-sm text-n-slate-11">
        {{ $t(`${KEY}.DROP_HINT`) }}
        <span class="hidden md:inline">{{ $t(`${KEY}.DROP_WHERE`) }}</span>
      </span>
    </button>

    <p
      v-if="error"
      data-create-media-error
      role="alert"
      class="m-0 text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>

    <!-- Segunda opção: imagens que a conta já usou em anúncios. Fechada até a pessoa pedir. -->
    <template v-if="props.library.length">
      <button
        type="button"
        data-create-media-library-toggle
        :aria-expanded="showLibrary"
        class="-ml-3 inline-flex min-h-11 items-start gap-2 self-start rounded-lg border-0 bg-transparent px-3 py-3 text-left text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="showLibrary = !showLibrary"
      >
        <span
          :class="showLibrary ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.LIBRARY`) }}
      </button>
      <div v-if="showLibrary" class="flex flex-wrap gap-3">
        <button
          v-for="(image, index) in props.library"
          :key="image.hash"
          type="button"
          :data-create-image="image.hash"
          :aria-pressed="media?.hash === image.hash"
          :aria-label="
            $t(`${KEY}.LIBRARY_PICK`, {
              number: index + 1,
              total: props.library.length,
            })
          "
          class="size-20 overflow-hidden rounded-xl border-0 p-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2"
          :class="
            media?.hash === image.hash
              ? 'ring-4 ring-n-brand'
              : 'ring-1 ring-n-weak'
          "
          @click="useLibrary(image)"
        >
          <img :src="image.url" alt="" class="size-full object-cover" />
        </button>
      </div>
    </template>
  </div>
</template>
