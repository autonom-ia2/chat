<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ImportStepDots from './ImportStepDots.vue';

const props = defineProps({
  suggestion: { type: String, default: '' },
  html: { type: String, default: '' },
  errorText: { type: String, default: '' },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'back']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN.NAME';
const name = ref(props.suggestion);

watch(
  () => props.suggestion,
  value => {
    if (value && !name.value) name.value = value;
  }
);

const save = () => {
  if (!name.value.trim() || props.isSaving) return;
  emit('save', name.value.trim());
};
</script>

<template>
  <form class="mx-auto w-full max-w-[40rem]" @submit.prevent="save">
    <ImportStepDots :current="3" />
    <h1
      class="mb-2 mt-4 text-2xl font-semibold tracking-tight text-n-slate-12 sm:text-[1.75rem]"
    >
      {{ t(`${S}.TITLE`) }}
    </h1>
    <p class="mb-5 text-base text-n-slate-11">{{ t(`${S}.LEAD`) }}</p>
    <div
      class="flex items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-3.5 shadow-sm"
    >
      <div
        class="relative size-28 shrink-0 overflow-hidden rounded-xl border border-n-weak bg-n-alpha-1 sm:size-32"
        aria-hidden="true"
      >
        <iframe
          v-if="html"
          :srcdoc="html"
          :title="t(`${S}.LABEL`)"
          sandbox=""
          referrerpolicy="no-referrer"
          tabindex="-1"
          class="pointer-events-none h-[40rem] w-[37.5rem] origin-top-left scale-[0.2] border-0 bg-white"
        />
      </div>
      <label class="flex min-w-0 flex-1 flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">{{
          t(`${S}.LABEL`)
        }}</span>
        <input
          v-model="name"
          type="text"
          maxlength="120"
          class="m-0 min-h-12 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 text-base text-n-slate-12 focus:border-n-brand"
          :aria-invalid="Boolean(errorText)"
        />
      </label>
    </div>
    <p
      v-if="errorText"
      class="mb-0 mt-3 text-sm font-medium text-n-ruby-11"
      role="alert"
    >
      {{ errorText }}
    </p>
    <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
      <Button
        type="button"
        :label="t(`${S}.AGAIN`)"
        icon="i-lucide-arrow-left"
        ghost
        class="!min-h-11"
        @click="emit('back')"
      />
      <Button
        type="submit"
        :label="t(`${S}.SAVE`)"
        icon="i-lucide-bookmark"
        size="lg"
        class="!min-h-12 !rounded-xl"
        :disabled="!name.trim()"
        :is-loading="isSaving"
      />
    </div>
  </form>
</template>
