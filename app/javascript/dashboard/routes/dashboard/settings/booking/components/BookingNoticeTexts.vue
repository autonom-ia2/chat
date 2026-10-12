<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingChoiceCards from './BookingChoiceCards.vue';
import BookingNoticeTextCard from './BookingNoticeTextCard.vue';

// Texto de cada aviso ativo (#1354). Uma linha diz quando ele vale (mensagem
// comum; fora das 24 h do WhatsApp oficial vai o modelo aprovado), o jeito de
// escrever da IA em cartões e um cartão por aviso.
const props = defineProps({
  form: { type: Object, required: true },
  kinds: { type: Array, required: true },
  setup: { type: Object, required: true },
  pageId: { type: Number, default: null },
});

const emit = defineEmits(['change']);
const { t } = useI18n();

const TONES = ['curto', 'simpatico', 'formal'];
const tone = ref('simpatico');
const toneChoices = computed(() =>
  TONES.map(value => ({
    value,
    label: t(`BOOKING.NOTICES.TEXTS.TONES.${value.toUpperCase()}.LABEL`),
    hint: t(`BOOKING.NOTICES.TEXTS.TONES.${value.toUpperCase()}.HINT`),
  }))
);

const changeText = (kind, text) => {
  const others = Object.fromEntries(
    Object.entries(props.form.noticeTexts || {}).filter(([key]) => key !== kind)
  );
  emit('change', {
    noticeTexts: text ? { ...others, [kind]: text } : others,
  });
};
</script>

<template>
  <section data-notice-texts class="flex flex-col gap-4">
    <div class="flex flex-col gap-2">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.NOTICES.TEXTS.TITLE') }}
      </h3>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.NOTICES.TEXTS.WINDOW_NOTE') }}
      </p>
    </div>
    <BookingChoiceCards
      data-notice-tone
      :legend="t('BOOKING.NOTICES.TEXTS.TONE_LABEL')"
      :options="toneChoices"
      :model-value="tone"
      @update:model-value="tone = $event"
    />
    <BookingNoticeTextCard
      v-for="kind in kinds"
      :key="kind"
      :kind="kind"
      :text="form.noticeTexts?.[kind] || ''"
      :setup="setup"
      :tone="tone"
      :page-id="pageId"
      @change="changeText(kind, $event)"
    />
  </section>
</template>
