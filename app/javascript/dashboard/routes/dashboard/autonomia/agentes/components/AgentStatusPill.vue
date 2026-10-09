<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({ code: { type: String, required: true } });
const { t } = useI18n();
const statuses = {
  E1: 'todo',
  E2: 'todo',
  E2m: 'todo',
  E3: 'todo',
  E4: 'ready',
  E5: 'active',
  E6: 'paused',
};
const styles = {
  todo: 'bg-n-amber-3 text-n-amber-12',
  ready: 'bg-n-blue-3 text-n-blue-12',
  active: 'bg-n-teal-3 text-n-teal-12',
  paused: 'bg-n-slate-3 text-n-slate-11',
};
const dots = {
  todo: 'bg-n-amber-9',
  ready: 'bg-n-brand',
  active: 'bg-n-teal-9',
  paused: 'bg-n-slate-9',
};
const status = computed(() => statuses[props.code]);
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 px-2.5 py-1 text-[0.8125rem] font-semibold rounded-full"
    :class="styles[status]"
  >
    <span
      class="size-1.5 rounded-full"
      :class="dots[status]"
      aria-hidden="true"
    />
    {{ t(`AGENTS.V2.status.${status}`) }}
  </span>
</template>
