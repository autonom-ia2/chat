<script setup>
// Mantém a API antiga do Select (options/groups/placeholder/error/ariaLabel),
// mas desenha o ChoiceSelect: nada de select nativo no produto.
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

defineProps({
  options: {
    type: Array,
    default: () => [],
    validator: options =>
      options.every(
        opt => typeof opt === 'object' && 'value' in opt && 'label' in opt
      ),
  },
  groups: {
    type: Array,
    default: () => [],
    validator: groups =>
      groups.every(
        group =>
          'label' in group &&
          Array.isArray(group.options) &&
          group.options.every(opt => 'value' in opt && 'label' in opt)
      ),
  },
  placeholder: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
  ariaLabel: {
    type: String,
    default: '',
  },
});

const modelValue = defineModel({
  type: [String, Number, Boolean],
  default: '',
});
</script>

<template>
  <div class="w-fit">
    <ChoiceSelect
      v-model="modelValue"
      class="w-full"
      :options="options"
      :groups="groups"
      :placeholder="placeholder"
      :disabled="disabled"
      :invalid="Boolean(error)"
      :aria-label="ariaLabel || placeholder"
    />
  </div>
</template>
