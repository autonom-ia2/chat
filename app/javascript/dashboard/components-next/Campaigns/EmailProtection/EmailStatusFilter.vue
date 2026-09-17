<script setup>
import { useI18n } from 'vue-i18n';
import {
  NS,
  CAMPAIGN_STATUSES,
  RECIPIENT_STATUSES,
  statusKey,
} from './presentation';
const props = defineProps({
  modelValue: { type: String, default: '' },
  campaign: Boolean,
  deliveryMode: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const label = value => {
  if (!value) return t(`${NS}.ALL`);
  if (value === 'attention') return t(`${NS}.ATTENTION`);
  if (value === 'bounced') return t(`${NS}.STATUS.bounced`);
  if (value === 'paused') return t(`${NS}.STATUS.paused_unknown`);
  return t(
    `${NS}.STATUS.${statusKey({ status: value, delivery_mode: props.deliveryMode }, props.campaign)}`
  );
};
</script>

<template>
  <label class="flex flex-col min-w-0 gap-1 text-sm text-n-slate-12">
    <span>{{
      t(`${NS}.${campaign ? 'CAMPAIGN_STATUS' : 'CURRENT_STATUS'}`)
    }}</span>
    <select
      :value="modelValue"
      class="h-10 max-w-full px-3 border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
      @change="emit('update:modelValue', $event.target.value)"
    >
      <option
        v-for="status in campaign ? CAMPAIGN_STATUSES : RECIPIENT_STATUSES"
        :key="status"
        :value="status"
      >
        {{ label(status) }}
      </option>
    </select>
  </label>
</template>
