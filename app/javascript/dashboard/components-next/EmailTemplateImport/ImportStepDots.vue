<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  current: { type: Number, required: true },
  total: { type: Number, default: 3 },
});

const { t } = useI18n();
</script>

<template>
  <div class="flex items-center gap-1.5">
    <span
      v-for="index in total"
      :key="index"
      class="h-1.5 w-7 rounded-full"
      :class="index <= current ? 'bg-n-brand' : 'bg-n-slate-5'"
      aria-hidden="true"
    />
    <span class="ms-1.5 text-sm text-n-slate-11">
      {{ t('EMAIL_IMPORT.SCREEN.STEP', { current, total }) }}
    </span>
  </div>
</template>
