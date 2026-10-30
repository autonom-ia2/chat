<script setup>
// The request, always in sight after "Conte" (#2277): a dark band in the same blue as the hero of the first
// step, so the three steps read as one journey. Same box in "Confira" and "Revise". On "Confira" it repeats the
// person's own words and the period (the card below says how they were understood); on "Revise" it shows the
// rule the list follows, in two lines at most, so the people show up on the first screen of a phone.
import { useI18n } from 'vue-i18n';

defineProps({
  understood: { type: String, default: '' },
  request: { type: String, required: true },
  period: { type: String, required: true },
});

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const { t } = useI18n();
</script>

<template>
  <section
    class="relative flex flex-col gap-1 overflow-hidden rounded-3xl bg-[#0D2344] px-5 py-4 text-white md:px-8"
    data-test="search-band"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-8 -top-14 size-36 rounded-full border-[1.5rem] border-n-blue-9 opacity-15"
    />
    <span class="relative text-sm font-medium text-white/60">
      {{ understood ? t(`${NS}.LIST_RULE`) : t(`${NS}.YOU_ASKED`) }}
    </span>
    <p
      class="relative m-0 line-clamp-2 text-base font-semibold leading-snug text-white md:text-lg"
    >
      {{ understood || request }}
    </p>
    <span
      v-if="!understood"
      class="relative mt-1 inline-flex w-fit items-center gap-1.5 rounded-full bg-white/10 px-3 py-1 text-sm text-white/85"
    >
      <span class="i-lucide-calendar size-4" aria-hidden="true" />
      {{ t(`${NS}.PERIOD_WORDS.${period.toUpperCase()}`) }}
    </span>
  </section>
</template>
