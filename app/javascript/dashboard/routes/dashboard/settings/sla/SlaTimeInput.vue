<script>
import validations from './validations';
import { useVuelidate } from '@vuelidate/core';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

export default {
  components: {
    ChoiceSelect,
  },
  props: {
    threshold: {
      type: Number,
      default: null,
    },
    thresholdUnit: {
      type: String,
      default: 'Minutes',
    },
    label: {
      type: String,
      default: '',
    },
    placeholder: {
      type: String,
      default: '',
    },
  },
  emits: ['unit', 'isInValid', 'updateThreshold'],
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      thresholdTime: this.threshold || '',
      thresholdUnitValue: this.thresholdUnit,
    };
  },
  validations,
  computed: {
    options() {
      return [
        { value: 'Minutes', label: this.$t('CRM_SLA.TIME_UNITS.MINUTES') },
        { value: 'Hours', label: this.$t('CRM_SLA.TIME_UNITS.HOURS') },
        { value: 'Days', label: this.$t('CRM_SLA.TIME_UNITS.DAYS') },
      ];
    },
    thresholdTimeErrorMessage() {
      let errorMessage = '';
      if (this.v$.thresholdTime.$error) {
        if (!this.v$.thresholdTime.numeric || !this.v$.thresholdTime.minValue) {
          errorMessage = this.$t(
            'SLA.FORM.THRESHOLD_TIME.INVALID_FORMAT_ERROR'
          );
        }
      }
      return errorMessage;
    },
  },
  watch: {
    threshold: {
      immediate: true,
      handler(value) {
        if (!Number.isNaN(value)) {
          this.thresholdTime = value;
        }
      },
    },
    thresholdUnit: {
      immediate: true,
      handler(value) {
        this.thresholdUnitValue = value;
      },
    },
  },
  methods: {
    onThresholdUnitChange() {
      this.$emit('unit', this.thresholdUnitValue);
    },
    onThresholdTimeChange() {
      this.v$.thresholdTime.$touch();
      const isInvalid = this.v$.thresholdTime.$invalid;
      this.$emit('isInValid', isInvalid);
      this.$emit(
        'updateThreshold',
        this.thresholdTime ? Number(this.thresholdTime) : null
      );
    },
  },
};
</script>

<template>
  <div class="flex items-center w-full gap-3">
    <woot-input
      v-model="thresholdTime"
      type="number"
      :class="{ error: v$.thresholdTime.$error }"
      class="flex-grow"
      :styles="{
        borderRadius: '0.75rem',
        padding: '0.375rem 0.75rem',
        fontSize: '0.875rem',
      }"
      :label="label"
      :placeholder="placeholder"
      :error="thresholdTimeErrorMessage"
      @update:model-value="onThresholdTimeChange"
    />
    <!-- the mt-7 handles the label offset -->
    <div class="mt-7">
      <ChoiceSelect
        v-model="thresholdUnitValue"
        :options="options"
        :aria-label="$t('SLA.FORM.THRESHOLD_TIME.UNIT')"
        @change="onThresholdUnitChange"
      />
    </div>
  </div>
</template>
