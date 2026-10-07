<script setup>
// "Nova campanha" with a campaign left unfinished (#1093): one simple question inside the page,
// never a browser dialog. Continuar essa resumes where the person stopped; Começar uma nova
// starts empty. An e-mail already created stays in the e-mail list either way.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  title: { type: String, default: '' },
  hasEmail: { type: Boolean, default: false },
});

const emit = defineEmits(['continue', 'startNew']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.RESUME';
const { t } = useI18n();

const name = computed(() => props.title.trim() || t(`${NS}.NO_NAME`));
</script>

<template>
  <section
    class="mx-auto mt-2 flex w-full max-w-xl flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm sm:mt-6 sm:p-8"
    data-test="draft-resume"
    aria-labelledby="draft-resume-title"
  >
    <span
      class="flex size-12 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
      aria-hidden="true"
    >
      <span class="i-lucide-file-pen-line size-6" />
    </span>
    <h2
      id="draft-resume-title"
      class="m-0 text-xl font-semibold leading-snug text-n-slate-12"
    >
      {{ t(`${NS}.TITLE`, { name }) }}
    </h2>
    <div class="flex flex-col gap-3 sm:flex-row">
      <Button
        :label="t(`${NS}.CONTINUE`)"
        class="!min-h-11 !rounded-xl sm:flex-1"
        data-test="draft-continue"
        @click="emit('continue')"
      />
      <Button
        :label="t(`${NS}.START_NEW`)"
        variant="outline"
        color="slate"
        class="!min-h-11 !rounded-xl sm:flex-1"
        data-test="draft-start-new"
        @click="emit('startNew')"
      />
    </div>
    <p v-if="hasEmail" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.EMAIL_KEPT`) }}
    </p>
  </section>
</template>
