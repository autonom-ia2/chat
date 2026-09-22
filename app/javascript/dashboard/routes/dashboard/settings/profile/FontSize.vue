<script setup>
import { computed } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useFontSize } from 'dashboard/composables/useFontSize';

const props = defineProps({
  value: {
    type: String,
    default: 'default',
  },
  label: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['change']);

const { fontSizeOptions } = useFontSize();

const selectedValue = computed({
  get: () => props.value,
  set: value => {
    emit('change', value);
  },
});
</script>

<template>
  <div class="flex gap-2 justify-between w-full items-start">
    <div>
      <label class="text-n-gray-12 font-medium leading-6 text-sm">
        {{ label }}
      </label>
      <p class="text-n-gray-11">
        {{ description }}
      </p>
    </div>
    <ChoiceSelect
      v-model="selectedValue"
      :options="fontSizeOptions"
      :aria-label="label"
    />
  </div>
</template>
