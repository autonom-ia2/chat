<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  CAROUSEL_MAX,
  MEDIA_ACCEPT,
  lerMidia,
  soltarMidia,
} from '../midiaDoAnuncio';
import { enviarMidia } from '../criacaoNaMeta';
import MetaAdsPreviewMedia from './MetaAdsPreviewMedia.vue';

// Anúncios da Meta (#2198), anúncio novo: mais fotos ou vídeos viram carrossel (de 2 a 10 cartões; a pessoa passa
// para o lado). O primeiro cartão é a mídia já escolhida; aqui ficam os outros, com o botão de tirar. Cada arquivo
// sobe para a Meta assim que a pessoa escolhe; só depois vira cartão.
const props = defineProps({
  first: { type: Object, required: true },
});

// `uploading`: enquanto sobe, o "Continuar" espera.
const emit = defineEmits(['uploading']);

const extra = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.MEDIA';
const input = ref(null);
const error = ref('');
const uploading = ref(false);
let mounted = true;

const setUploading = value => {
  uploading.value = value;
  emit('uploading', value);
};

const cards = computed(() => [props.first, ...extra.value]);
const full = computed(() => cards.value.length >= CAROUSEL_MAX);

const add = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  error.value = '';
  if (!file) return;
  let media = null;
  try {
    media = await lerMidia(file);
  } catch (refused) {
    error.value = t(`${KEY}.ERRORS.${refused.code || 'READ'}`, {
      max: refused.max,
    });
    return;
  }
  setUploading(true);
  try {
    const sent = await enviarMidia(media, file);
    if (mounted) extra.value = [...extra.value, sent];
    else soltarMidia(media);
  } catch {
    soltarMidia(media);
    error.value = t(`${KEY}.ERRORS.UPLOAD`);
  } finally {
    if (mounted) setUploading(false);
  }
};

// Saiu da tela no meio do envio: o resultado não volta mais, e o "Continuar" não fica esperando.
onBeforeUnmount(() => {
  mounted = false;
  if (uploading.value) emit('uploading', false);
});

const remove = index => {
  soltarMidia(extra.value[index]);
  extra.value = extra.value.filter((_, position) => position !== index);
};
</script>

<template>
  <div data-create-carousel class="flex min-w-0 flex-col gap-2">
    <ol
      v-if="extra.length"
      class="m-0 flex list-none gap-2 overflow-x-auto p-0 pb-1"
      :aria-label="$t(`${KEY}.CAROUSEL.LABEL`, { count: cards.length })"
    >
      <li
        v-for="(card, index) in cards"
        :key="card.url + index"
        :data-create-carousel-card="index + 1"
        class="relative size-20 shrink-0 overflow-hidden rounded-xl bg-n-alpha-2"
      >
        <MetaAdsPreviewMedia :media="card" />
        <span
          class="absolute left-1 top-1 rounded-md bg-n-black/60 px-1.5 text-xs font-semibold text-white"
        >
          {{ index + 1 }}
        </span>
        <button
          v-if="index > 0"
          type="button"
          :data-create-carousel-remove="index + 1"
          :aria-label="$t(`${KEY}.CAROUSEL.REMOVE`, { number: index + 1 })"
          class="absolute right-0 top-0 grid size-11 place-items-center border-0 bg-transparent p-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="remove(index - 1)"
        >
          <span
            class="grid size-6 place-items-center rounded-full bg-n-black/60 text-white"
          >
            <span class="i-lucide-x size-3.5" aria-hidden="true" />
          </span>
        </button>
      </li>
    </ol>
    <input
      ref="input"
      type="file"
      class="hidden"
      data-create-carousel-input
      :accept="MEDIA_ACCEPT"
      @change="add"
    />
    <p
      v-if="uploading"
      data-create-carousel-uploading
      role="status"
      class="m-0 flex min-h-11 items-center gap-3 text-sm text-n-slate-12"
    >
      <Spinner :size="20" class="shrink-0 text-n-brand" />
      {{ $t(`${KEY}.UPLOADING`) }}
    </p>
    <button
      v-else-if="!full"
      type="button"
      data-create-carousel-add
      class="-ml-3 inline-flex min-h-11 items-start gap-2 self-start rounded-lg border-0 bg-transparent px-3 py-3 text-left text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="input?.click()"
    >
      <span class="i-lucide-plus mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ $t(`${KEY}.CAROUSEL.ADD`) }}
    </button>
    <p class="m-0 text-xs text-n-slate-11">
      {{ full ? $t(`${KEY}.CAROUSEL.FULL`) : $t(`${KEY}.CAROUSEL.HINT`) }}
    </p>
    <p
      v-if="error"
      data-create-carousel-error
      role="alert"
      class="m-0 text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
  </div>
</template>
