<script setup>
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { fieldValue } from './presentation';

const props = defineProps({
  definitions: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  errors: { type: Object, default: () => ({}) },
});
const values = defineModel({ type: Object, default: () => ({}) });
const { t } = useI18n();
const options = definition => [
  { value: '', label: t('RELATIONSHIPS.EMPTY') },
  ...(definition.attribute_display_type === 'checkbox'
    ? [
        { value: true, label: t('RELATIONSHIPS.YES') },
        { value: false, label: t('RELATIONSHIPS.NO') },
      ]
    : definition.attribute_values.map(value => ({ value, label: value }))),
];
const inputType = definition =>
  ({
    number: 'number',
    currency: 'number',
    percent: 'number',
    date: 'date',
    link: 'url',
  })[definition.attribute_display_type] || 'text';
const update = (definition, value) => {
  values.value = {
    ...values.value,
    [definition.attribute_key]: fieldValue(
      definition.attribute_display_type,
      value
    ),
  };
};
const invalid = definition =>
  Boolean(props.errors[`custom_attributes.${definition.attribute_key}`]);
</script>

<template>
  <div
    v-for="definition in definitions"
    :key="definition.id"
    class="grid min-w-0 gap-2"
    :data-draft-attribute="definition.attribute_key"
  >
    <label
      v-if="['list', 'checkbox'].includes(definition.attribute_display_type)"
      class="grid min-w-0 gap-2 text-sm text-n-slate-12"
    >
      <span>{{ definition.attribute_display_name }}</span>
      <ChoiceSelect
        :model-value="values[definition.attribute_key] ?? ''"
        :options="options(definition)"
        :aria-label="definition.attribute_display_name"
        :disabled="disabled"
        :invalid="invalid(definition)"
        @update:model-value="update(definition, $event)"
      />
    </label>
    <Input
      v-else
      :model-value="values[definition.attribute_key] ?? ''"
      :label="definition.attribute_display_name"
      :type="inputType(definition)"
      step="any"
      :disabled="disabled"
      :aria-invalid="invalid(definition) || undefined"
      @update:model-value="update(definition, $event)"
    />
    <p
      v-if="definition.attribute_description"
      class="m-0 text-xs leading-5 text-n-slate-11"
    >
      {{ definition.attribute_description }}
    </p>
    <p
      v-if="invalid(definition)"
      role="alert"
      class="m-0 text-xs text-n-ruby-11"
    >
      {{ t('CRM_KANBAN.OPPORTUNITY.REGISTRATION.INVALID_FIELD') }}
    </p>
  </div>
</template>
