<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { botaoDoAnuncio, ofertaNoTexto, textoDaOferta } from '../anuncioNovo';
import { CAROUSEL_DESTINATIONS } from '../midiaDoAnuncio';
import MetaAdsAdPreview from './MetaAdsAdPreview.vue';
import MetaAdsCarouselCards from './MetaAdsCarouselCards.vue';
import MetaAdsCreateDestination from './MetaAdsCreateDestination.vue';
import MetaAdsMediaPicker from './MetaAdsMediaPicker.vue';

// Anúncios da Meta (#2198), anúncio novo: para onde vai quem toca (uma linha no topo, WhatsApp já marcado), o que a
// pessoa vende, a foto ou o vídeo (do celular, ou uma imagem de anúncio antigo; com mais de uma, carrossel) e o
// texto, com a prévia ao lado (embaixo, no celular). O texto e o título saem do que ela vende ("bolo de pote a
// R$ 12" → "Bolo de pote a R$ 12. Chame no WhatsApp e faça seu pedido.") até ela mexer neles. No WhatsApp, a
// mensagem que a pessoa manda já vem escrita. Como os três já vêm prontos, a tela mostra só um resumo ("Texto pronto:
// «…» · Mudar texto"), e o "Mudar texto" abre o texto, o título e a mensagem.
defineProps({
  library: { type: Array, default: () => [] },
  pageName: { type: String, default: '' },
  phone: { type: String, default: '' },
  hasNumber: { type: Boolean, default: true },
  instagram: { type: Object, default: null },
  destinations: { type: Array, required: true },
});

const draft = defineModel({ type: Object, required: true });

const { t } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT';

const editingText = ref(false);
const textFields = ref(null);
const editText = async () => {
  editingText.value = true;
  await nextTick();
  textFields.value?.querySelector('textarea')?.focus();
};

const set = (field, value) => {
  draft.value = { ...draft.value, [field]: value };
};

const setOffer = value => {
  const current = draft.value;
  draft.value = {
    ...current,
    offer: value,
    text: current.text_edited
      ? current.text
      : textoDaOferta(t, value, current.destination),
    headline: current.headline_edited ? current.headline : ofertaNoTexto(value),
  };
};

const setEdited = (field, value) => {
  draft.value = { ...draft.value, [field]: value, [`${field}_edited`]: true };
};

// Sem a primeira mídia, o carrossel some junto.
const setMedia = media => {
  draft.value = {
    ...draft.value,
    media,
    more_media: media ? draft.value.more_media : [],
  };
};

const allowsCarousel = computed(
  () =>
    Boolean(draft.value.media) &&
    CAROUSEL_DESTINATIONS.includes(draft.value.destination)
);
const cards = computed(() =>
  draft.value.media ? [draft.value.media, ...draft.value.more_media] : []
);
</script>

<template>
  <div
    class="grid min-w-0 grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
  >
    <div class="flex min-w-0 flex-col gap-5">
      <MetaAdsCreateDestination
        v-model="draft"
        :phone="phone"
        :has-number="hasNumber"
        :instagram="instagram"
        :destinations="destinations"
      />
      <Input
        :model-value="draft.offer"
        data-create-offer
        :label="$t(`${KEY}.OFFER`)"
        :placeholder="$t(`${KEY}.OFFER_PLACEHOLDER`)"
        :message="$t(`${KEY}.OFFER_HINT`)"
        wrap-message
        @update:model-value="setOffer"
      />
      <div class="flex min-w-0 flex-col gap-2">
        <MetaAdsMediaPicker
          :model-value="draft.media"
          :library="library"
          @update:model-value="setMedia"
          @uploading="set('uploading_media', $event)"
        />
        <MetaAdsCarouselCards
          v-if="allowsCarousel"
          :model-value="draft.more_media"
          :first="draft.media"
          @update:model-value="set('more_media', $event)"
          @uploading="set('uploading_cards', $event)"
        />
      </div>
      <div
        v-if="!editingText"
        data-create-text-summary
        class="flex min-w-0 flex-col items-start gap-1 rounded-xl bg-n-alpha-1 p-4"
      >
        <p class="m-0 line-clamp-2 break-words text-sm text-n-slate-12">
          {{
            draft.text
              ? $t(`${KEY}.TEXT_READY`, { text: draft.text })
              : $t(`${KEY}.TEXT_READY_EMPTY`)
          }}
        </p>
        <button
          type="button"
          data-create-text-edit
          class="-my-2 inline-flex min-h-11 items-center gap-1.5 rounded-lg border-0 bg-transparent p-0 text-sm font-520 text-n-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="editText"
        >
          <span class="i-lucide-pencil size-4" aria-hidden="true" />
          {{ $t(`${KEY}.TEXT_CHANGE`) }}
        </button>
      </div>
      <div v-else ref="textFields" class="flex min-w-0 flex-col gap-5">
        <TextArea
          :model-value="draft.text"
          data-create-text
          :label="$t(`${KEY}.TEXT`)"
          :placeholder="$t(`${KEY}.TEXT_PLACEHOLDER`)"
          :max-length="500"
          show-character-count
          min-height="6rem"
          custom-text-area-wrapper-class="min-w-0"
          @update:model-value="setEdited('text', $event)"
        />
        <Input
          :model-value="draft.headline"
          data-create-headline
          :label="$t(`${KEY}.HEADLINE`)"
          :placeholder="$t(`${KEY}.HEADLINE_PLACEHOLDER`)"
          :message="$t(`${KEY}.HEADLINE_HINT`)"
          wrap-message
          @update:model-value="setEdited('headline', $event)"
        />
        <Input
          v-if="draft.destination === 'WHATSAPP'"
          :model-value="draft.ready_message"
          data-create-ready-message
          :label="$t(`${KEY}.READY_MESSAGE`)"
          :message="$t(`${KEY}.READY_MESSAGE_HINT`)"
          wrap-message
          @update:model-value="set('ready_message', $event)"
        />
      </div>
    </div>
    <MetaAdsAdPreview
      :page-name="pageName"
      :text="draft.text || $t(`${KEY}.TEXT_PLACEHOLDER`)"
      :media="draft.media"
      :cards="cards"
      :headline="draft.headline || $t(`${KEY}.HEADLINE_PLACEHOLDER`)"
      :action="botaoDoAnuncio(draft)"
      :places="draft.placement"
    />
  </div>
</template>
