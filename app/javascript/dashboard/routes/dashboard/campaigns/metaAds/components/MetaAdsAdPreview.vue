<script setup>
import { computed, nextTick, ref } from 'vue';
import { DESTINATION_ICONS } from '../anuncioNovo';
import { formatoDaMidia } from '../midiaDoAnuncio';
import MetaAdsPreviewMedia from './MetaAdsPreviewMedia.vue';

// Anúncios da Meta (#2198): como o anúncio aparece em cada lugar — no feed e nos Stories e Reels, em tela cheia na
// vertical — no Instagram e no Facebook, ou só num deles. Foto que não é vertical aparece inteira no centro dos
// Stories, com o fundo preenchido; a frase embaixo diz isso sem prometer o que a Meta faz (o ajuste dela não está
// documentado para estes anúncios). O botão segue o destino (WhatsApp, Direct, Messenger ou o texto do site). Com
// mais de uma mídia, o feed mostra o carrossel. Post impulsionado do Facebook aparece só no feed.
const props = defineProps({
  pageName: { type: String, default: '' },
  text: { type: String, default: '' },
  // { kind: 'image' | 'video', url, poster, width, height }
  media: { type: Object, default: null },
  // Carrossel: todas as mídias, a primeira inclusive. Com uma só, anúncio comum.
  cards: { type: Array, default: () => [] },
  headline: { type: String, default: '' },
  // O botão: WHATSAPP, INSTAGRAM_DIRECT, MESSENGER, LEARN_MORE, SHOP_NOW, ou null (leva ao post).
  action: { type: String, default: null },
  // Onde aparece: AUTO (Instagram e Facebook), INSTAGRAM ou FACEBOOK.
  places: { type: String, default: 'AUTO' },
  // Só o feed, sem abas: post impulsionado do Facebook.
  feedOnly: { type: Boolean, default: false },
});

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PREVIEW';
const PLACES = ['FEED', 'STORIES'];
const place = ref('FEED');

const isCarousel = computed(() => props.cards.length > 1);
const shape = computed(() =>
  props.media ? formatoDaMidia(props.media) : 'SQUARE'
);
const vertical = computed(() => shape.value === 'VERTICAL');
// O feed mostra até 4:5: foto vertical aparece cortada em cima e embaixo.
const feedFrame = computed(() =>
  ['VERTICAL', 'PORTRAIT'].includes(shape.value)
    ? 'aspect-[4/5]'
    : 'aspect-square'
);
const showFeed = computed(() => props.feedOnly || place.value === 'FEED');

const SITE_ACTIONS = ['LEARN_MORE', 'SHOP_NOW'];
const button = computed(() => {
  if (!props.action) return null;
  const isSite = SITE_ACTIONS.includes(props.action);
  return {
    icon: isSite ? 'i-lucide-external-link' : DESTINATION_ICONS[props.action],
    label: isSite
      ? `CRM_KANBAN.META_ADS_HUB.CRIAR.DESTINATION.ACTIONS.${props.action}`
      : `${KEY}.CTA`,
  };
});

const note = computed(() => {
  if (props.feedOnly) return 'NOTE_FEED_FACEBOOK';
  if (isCarousel.value) return 'NOTE_CAROUSEL';
  if (place.value === 'FEED') {
    return vertical.value ? 'NOTE_FEED_VERTICAL' : 'NOTE_FEED';
  }
  if (vertical.value) return 'NOTE_STORIES_VERTICAL';
  return shape.value === 'PORTRAIT'
    ? 'NOTE_STORIES_PORTRAIT'
    : 'NOTE_STORIES_FIT';
});

// Abas no padrão WAI-ARIA: ←/→ trocam e levam o foco junto.
const uid = Math.random().toString(36).slice(2, 8);
const tabs = ref([]);
const move = async step => {
  const index =
    (PLACES.indexOf(place.value) + step + PLACES.length) % PLACES.length;
  place.value = PLACES[index];
  await nextTick();
  tabs.value[index]?.focus();
};
</script>

<template>
  <aside
    data-create-preview
    class="flex min-w-0 flex-col gap-3 self-start"
    :aria-label="$t(`${KEY}.LABEL`)"
  >
    <p
      data-create-preview-where
      class="m-0 flex items-center gap-1.5 text-xs font-medium text-n-slate-11"
    >
      <span
        v-if="places !== 'FACEBOOK'"
        class="i-ri-instagram-line size-4"
        aria-hidden="true"
      />
      <span
        v-if="places !== 'INSTAGRAM'"
        class="i-ri-facebook-circle-line size-4"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.WHERE.${places}`) }}
    </p>

    <div
      v-if="!feedOnly"
      role="tablist"
      :aria-label="$t(`${KEY}.LABEL`)"
      class="flex gap-1 self-start rounded-xl bg-n-alpha-2 p-1"
    >
      <button
        v-for="option in PLACES"
        :key="option"
        ref="tabs"
        type="button"
        role="tab"
        :data-create-preview-place="option"
        :aria-selected="place === option"
        :aria-controls="`previa-${uid}-${option}`"
        :tabindex="place === option ? 0 : -1"
        class="min-h-11 rounded-lg border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          place === option
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="place = option"
        @keydown.right.prevent="move(1)"
        @keydown.left.prevent="move(-1)"
      >
        {{ $t(`${KEY}.${option}`) }}
      </button>
    </div>

    <!-- Feed: nome da Página, texto, a mídia (ou o carrossel) e o botão. -->
    <div
      v-if="showFeed"
      :id="`previa-${uid}-FEED`"
      :role="feedOnly ? undefined : 'tabpanel'"
      data-create-preview-feed
      class="flex w-full max-w-sm flex-col overflow-hidden rounded-2xl bg-n-solid-2 ring-1 ring-n-weak"
    >
      <p class="m-0 px-4 pt-3 text-xs font-semibold text-n-slate-11">
        {{ pageName }}
        <span class="font-normal text-n-slate-10">
          {{ $t(`${KEY}.SPONSORED`) }}
        </span>
      </p>
      <p
        class="m-0 line-clamp-4 whitespace-pre-line break-words px-4 py-2 text-sm text-n-slate-12"
      >
        {{ text }}
      </p>
      <ol
        v-if="isCarousel"
        data-create-preview-carousel
        class="m-0 flex list-none snap-x gap-2 overflow-x-auto px-4 pb-3"
      >
        <li
          v-for="(card, index) in cards"
          :key="card.url + index"
          class="flex w-[78%] shrink-0 snap-start flex-col overflow-hidden rounded-xl bg-n-solid-2 ring-1 ring-n-weak"
        >
          <div
            class="relative aspect-square w-full bg-n-alpha-2 text-n-slate-11"
          >
            <MetaAdsPreviewMedia :media="card" fill />
          </div>
          <div class="flex flex-1 flex-col gap-2 px-3 py-2">
            <span
              class="line-clamp-2 min-h-8 break-words text-xs font-semibold text-n-slate-12"
            >
              {{ headline }}
            </span>
            <span
              v-if="button"
              class="mt-auto inline-flex items-center justify-center gap-1 rounded-lg bg-n-alpha-2 px-2 py-1.5 text-xs font-semibold text-n-slate-12"
            >
              <span :class="button.icon" class="size-3.5" aria-hidden="true" />
              {{ $t(button.label) }}
            </span>
          </div>
        </li>
      </ol>
      <template v-else>
        <div
          class="relative w-full bg-n-alpha-2 text-n-slate-11"
          :class="feedFrame"
        >
          <MetaAdsPreviewMedia :media="media" />
        </div>
        <div
          v-if="button"
          class="flex items-center justify-between gap-3 px-4 py-3"
        >
          <span
            class="min-w-0 break-words text-sm font-semibold text-n-slate-12"
          >
            {{ headline }}
          </span>
          <span
            class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-n-alpha-2 px-3 py-2 text-xs font-semibold text-n-slate-12"
          >
            <span :class="button.icon" class="size-4" aria-hidden="true" />
            {{ $t(button.label) }}
          </span>
        </div>
      </template>
    </div>

    <!-- Stories e Reels: tela cheia, na vertical, com o botão embaixo. -->
    <div
      v-else
      :id="`previa-${uid}-STORIES`"
      role="tabpanel"
      data-create-preview-stories
      class="relative aspect-[9/16] w-full max-w-[16rem] overflow-hidden rounded-[1.75rem] bg-n-slate-12 ring-4 ring-n-slate-12"
    >
      <div
        v-if="media && !vertical"
        class="absolute inset-0 scale-110 opacity-60 blur-xl"
      >
        <MetaAdsPreviewMedia :media="media" backdrop />
      </div>
      <div class="relative size-full text-white">
        <MetaAdsPreviewMedia
          :media="media"
          :fit="vertical ? 'cover' : 'contain'"
        />
      </div>
      <p
        class="absolute inset-x-0 top-0 m-0 bg-gradient-to-b from-n-black/60 to-transparent px-3 pb-6 pt-3 text-xs font-semibold text-white"
      >
        {{ pageName }}
        <span class="font-normal text-white/75">
          {{ $t(`${KEY}.SPONSORED`) }}
        </span>
      </p>
      <div
        class="absolute inset-x-0 bottom-0 flex flex-col gap-2 bg-gradient-to-t from-n-black/85 via-n-black/40 to-transparent px-3 pb-4 pt-12"
      >
        <span
          v-if="isCarousel"
          class="self-center text-xs font-semibold text-white/80"
        >
          {{ $t(`${KEY}.CAROUSEL_COUNT`, { count: cards.length }) }}
        </span>
        <!-- O fundo fica fora do corte: o line-clamp no próprio fundo deixava aparecer um pedaço da 3ª linha. -->
        <div class="rounded-lg bg-n-black/60 px-2 py-1">
          <p class="m-0 line-clamp-2 text-xs text-white">{{ text }}</p>
        </div>
        <span
          v-if="button"
          class="inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg bg-white text-xs font-semibold text-n-slate-12"
        >
          <span :class="button.icon" class="size-4" aria-hidden="true" />
          {{ $t(button.label) }}
        </span>
      </div>
    </div>

    <p data-create-preview-note class="m-0 max-w-sm text-xs text-n-slate-11">
      {{ $t(`${KEY}.${note}`, { where: $t(`${KEY}.IN.${places}`) }) }}
    </p>
  </aside>
</template>
