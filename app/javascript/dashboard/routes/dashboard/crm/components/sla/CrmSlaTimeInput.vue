<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  modelValue: { type: Number, default: null },
  unit: { type: String, default: 'Minutes' },
  enabled: { type: Boolean, default: false },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  showErrors: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:modelValue',
  'update:unit',
  'update:enabled',
  'invalid',
]);

const { t } = useI18n();

// Values stay 'Minutes' | 'Hours' | 'Days' to reuse the native seconds math.
const unitOptions = computed(() => [
  { value: 'Minutes', label: t('CRM_SLA.TIME_UNITS.MINUTES') },
  { value: 'Hours', label: t('CRM_SLA.TIME_UNITS.HOURS') },
  { value: 'Days', label: t('CRM_SLA.TIME_UNITS.DAYS') },
]);

// Same height as the unit ChoiceSelect (44 px) so the two line up.
const fieldClass =
  'reset-base box-border h-11 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand';

const dirty = ref(false);

const unitModel = computed({
  get: () => props.unit,
  set: value => emit('update:unit', value),
});

// A metric only blocks saving while it is toggled ON: it then needs a positive
// number. Toggled OFF it is simply not tracked (the engine skips blank thresholds).
const isInvalid = computed(
  () =>
    props.enabled &&
    (props.modelValue === null ||
      Number.isNaN(props.modelValue) ||
      props.modelValue <= 0)
);
watch(isInvalid, value => emit('invalid', value), { immediate: true });

const showInvalidMessage = computed(
  () => isInvalid.value && (dirty.value || props.showErrors)
);

const onThresholdInput = event => {
  dirty.value = true;
  const raw = event.target.value;
  const threshold = raw === '' || raw === null ? null : Number(raw);
  emit('update:modelValue', threshold);
};
</script>

<template>
  <div class="grid gap-1">
    <div class="flex min-h-10 items-center gap-3">
      <ToggleSwitch
        :model-value="enabled"
        @update:model-value="emit('update:enabled', $event)"
      />
      <span
        class="min-w-0 flex-1 truncate text-sm"
        :class="enabled ? 'text-n-slate-12' : 'text-n-slate-10'"
      >
        {{ label }}
      </span>
      <template v-if="enabled">
        <input
          :value="modelValue ?? ''"
          type="number"
          min="0"
          :placeholder="placeholder"
          :class="fieldClass"
          class="w-24 shrink-0 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
          @input="onThresholdInput"
        />
        <ChoiceSelect
          v-model="unitModel"
          :options="unitOptions"
          :aria-label="t('CRM_SLA.TIME_UNIT_LABEL', { metric: label })"
          class="w-32 shrink-0"
        />
      </template>
    </div>
    <p
      v-if="showInvalidMessage"
      class="mb-0 text-xs text-n-ruby-11 ltr:pl-12 rtl:pr-12"
    >
      {{ t('CRM_SLA.POLICIES.DIALOG.THRESHOLD_INVALID') }}
    </p>
  </div>
</template>
