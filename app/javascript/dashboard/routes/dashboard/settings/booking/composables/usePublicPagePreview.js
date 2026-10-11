import { computed, ref, watchEffect } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  applyBrandColor,
  clientTimeZone,
  provideFlow,
  publicMessages,
  sameClock,
} from '../publicPage';
import {
  previewDays,
  previewDurations,
  previewEarliest,
  previewZone,
  publicPageFrom,
} from '../bookingPreview';

const nothing = () => {};

// Faz as telas da página pública funcionarem dentro do painel (#1289), para a
// prévia ser a página de verdade e não um desenho parecido:
// - os textos da página pública entram no catálogo do painel (namespace
//   BOOKING_V2, que só ela usa);
// - a cor da marca é aplicada no elemento `root`, do mesmo jeito que a página
//   aplica nela inteira (helpers/brand.js);
// - as telas recebem um fluxo de mentira: mostram, mas nenhum botão faz nada.
export const usePublicPagePreview = ({ root, form, page }) => {
  const { mergeLocaleMessage } = useI18n({ useScope: 'global' });
  Object.entries(publicMessages).forEach(([locale, messages]) =>
    mergeLocaleMessage(locale, messages)
  );

  watchEffect(() => {
    if (root.value) applyBrandColor(form.value.color, root.value);
  });

  const publicPage = computed(() => publicPageFrom(form.value, page.value));
  const days = computed(() => previewDays(form.value, page.value));
  const durations = computed(() => previewDurations(form.value));
  const duration = computed(() => form.value.durationMinutes);
  const clientZone = clientTimeZone();
  const zone = computed(() => previewZone(page.value));
  const nextSlot = computed(() =>
    previewEarliest(days.value, form.value.startHour, zone.value)
  );
  // Como na página: as horas aparecem no relógio de quem abre, e a página
  // avisa quando ele é outro que o dela.
  const isOtherClock = computed(() => !sameClock(clientZone, zone.value));

  provideFlow({
    page: publicPage,
    days,
    durations,
    duration,
    slots: { nextSlot },
    greetingName: ref(''),
    clientZone,
    isOtherClock,
    chooseDay: nothing,
    chooseDuration: nothing,
    chooseEarliest: nothing,
    openNoSlot: nothing,
    manage: {
      isRescheduling: ref(false),
      isRebooking: ref(false),
      returnToManage: nothing,
    },
  });

  return { publicPage };
};
