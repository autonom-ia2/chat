<script setup>
// The end of the search by conversation (#2277): the audience is saved. One big confirmation, how many people
// and how many can be reached on WhatsApp, and the next step: a campaign with this audience already chosen.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  saved: { type: Object, required: true },
});
const emit = defineEmits(['create-campaign', 'see-audience']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const { t } = useI18n();
</script>

<template>
  <section
    class="flex flex-col items-center gap-4 rounded-3xl border border-n-weak bg-n-solid-1 px-5 py-10 text-center shadow-sm md:px-10"
    data-test="search-saved"
  >
    <span
      class="grid size-20 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-10" />
    </span>
    <h2 class="m-0 text-2xl font-bold text-n-slate-12 md:text-[2rem]">
      {{ t(`${NS}.SAVED_TITLE`) }}
    </h2>
    <p class="m-0 text-lg font-semibold text-n-slate-12">{{ saved.name }}</p>
    <p class="m-0 text-base text-n-slate-11">
      {{ t(`${NS}.SAVED_COUNTS`, { count: saved.count }) }}
    </p>
    <div class="mt-2 flex w-full flex-col gap-3 sm:w-auto sm:flex-row-reverse">
      <Button
        :label="t(`${NS}.SAVED_CREATE`, { count: saved.count })"
        icon="i-lucide-send"
        class="!h-auto !min-h-12 !whitespace-normal !rounded-xl !px-6 !py-2 !text-base"
        data-test="create-campaign"
        @click="emit('create-campaign')"
      />
      <Button
        :label="t(`${NS}.SAVED_SEE`)"
        variant="outline"
        color="slate"
        class="!min-h-12 !rounded-xl !px-6 !text-base"
        @click="emit('see-audience')"
      />
    </div>
  </section>
</template>
