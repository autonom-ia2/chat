<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import {
  NS,
  CAMPAIGN_STATUSES,
  RECIPIENT_STATUSES,
  PROBLEM_STATUSES,
  statusKey,
  displayStatusLabel,
} from './presentation';

const props = defineProps({
  modelValue: { type: String, default: '' },
  campaign: Boolean,
  problem: Boolean,
  deliveryMode: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const iconFor = value => {
  const icons = {
    '': 'i-lucide-list-filter',
    attention: 'i-lucide-circle-alert',
    pending: 'i-lucide-clock',
    delivered: 'i-lucide-circle-check',
    unsubscribed: 'i-lucide-user-minus',
    temporary_bounced: 'i-lucide-refresh-cw',
    hard_bounced: 'i-lucide-circle-x',
    complained: 'i-lucide-shield-alert',
    preflight_invalid: 'i-lucide-mail-x',
    preflight_review: 'i-lucide-circle-help',
  };
  return icons[value] || 'i-lucide-circle';
};

const label = value => {
  if (!value) return t(`${NS}.ALL`);
  if (value === 'attention') return t(`${NS}.STATUS.attention`);
  if (value === 'hard_bounced') return displayStatusLabel(t, 'permanent');
  if (value === 'temporary_bounced') return t(`${NS}.STATUS.temporary`);
  if (value === 'preflight_invalid') return t(`${NS}.STATUS.invalid`);
  if (value === 'preflight_review') return t(`${NS}.STATUS.review`);
  if (value === 'paused') return t(`${NS}.STATUS.paused_unknown`);
  if (value === 'delivered') {
    const delivery = statusKey(
      { status: 'delivered', delivery_mode: props.deliveryMode },
      false
    );
    return delivery === 'delivered'
      ? t('CAMPAIGN_MANAGEMENT.KPIS.DELIVERED')
      : displayStatusLabel(t, delivery);
  }
  const key = statusKey(
    { status: value, delivery_mode: props.deliveryMode },
    props.campaign
  );
  return displayStatusLabel(t, key);
};

const values = computed(() => {
  if (props.campaign) return CAMPAIGN_STATUSES;
  if (props.problem) return PROBLEM_STATUSES;
  return RECIPIENT_STATUSES;
});

const options = computed(() =>
  values.value.map(value => ({
    value,
    label: label(value),
    icon: iconFor(value),
  }))
);

const selectedOption = computed(
  () =>
    options.value.find(option => option.value === props.modelValue) ||
    options.value[0]
);

const fieldLabel = computed(() => {
  if (props.campaign) return t(`${NS}.CAMPAIGN_STATUS`);
  if (props.problem) return t(`${NS}.STATUS.attention`);
  return t('CAMPAIGN_MANAGEMENT.TABLE.STATUS');
});

const update = value => emit('update:modelValue', value);
</script>

<template>
  <div
    class="flex flex-col w-full min-w-0 gap-1"
    role="group"
    :aria-label="fieldLabel"
  >
    <span class="mb-0.5 text-heading-3 text-n-slate-12">{{ fieldLabel }}</span>
    <FilterSelect
      :model-value="modelValue"
      :options="options"
      hide-icon
      variant="faded"
      @update:model-value="update"
    >
      <template #trigger="{ toggle }">
        <Button
          type="button"
          md
          slate
          faded
          trailing-icon
          icon="i-lucide-chevron-down"
          class="!w-full !h-10 !justify-between"
          :label="selectedOption?.label"
          @click="toggle"
        />
      </template>
    </FilterSelect>
  </div>
</template>
