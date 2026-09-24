<script>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

export default {
  components: {
    ChoiceSelect,
  },
  props: {
    label: {
      type: String,
      default: '',
    },
    options: {
      type: Array,
      default: () => [],
    },
    selected: {
      type: String,
      default: '',
    },
    action: {
      type: Function,
      default: () => {},
    },
  },
  data() {
    return {
      value: this.selected,
    };
  },
  computed: {
    // As opções não tinham :value, então o valor era o próprio texto.
    choices() {
      return this.options.map(option => ({
        value: option.value,
        label: option.value,
      }));
    },
  },
};
</script>

<template>
  <div>
    <label>
      {{ label }}
    </label>
    <ChoiceSelect
      v-model="value"
      :options="choices"
      :aria-label="label"
      class="w-full mb-4"
      @change="action(value)"
    />
  </div>
</template>
