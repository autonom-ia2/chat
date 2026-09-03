<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { STATE_TONE, isTransientState } from '../insuranceContract';

const props = defineProps({
  state: { type: String, required: true },
});

const { t } = useI18n();

const toneClass = computed(() => {
  switch (STATE_TONE[props.state]) {
    case 'success':
      return 'bg-n-teal-3 text-n-teal-11';
    case 'warning':
      return 'bg-n-amber-3 text-n-amber-11';
    case 'danger':
      return 'bg-n-ruby-3 text-n-ruby-11';
    case 'info':
      return 'bg-n-iris-3 text-n-iris-11';
    default:
      return 'bg-n-alpha-2 text-n-slate-11';
  }
});

const label = computed(() =>
  t(`INSURANCE.CONNECTION.STATES.${props.state.toUpperCase()}`)
);
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-xs font-medium"
    :class="toneClass"
  >
    <span
      v-if="isTransientState(state)"
      class="i-lucide-loader-circle size-3 animate-spin"
    />
    <span v-else class="size-1.5 rounded-full bg-current" />
    {{ label }}
  </span>
</template>
