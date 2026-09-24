<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  // grapesjs-mjml Typography 'font-family' Property instance or undefined.
  property: {
    type: Object,
    default: null,
  },
  revision: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['change']);

const { t } = useI18n();

// Email-safe web fonts.
const FONTS = [
  'Arial',
  'Helvetica',
  'Georgia',
  'Times New Roman',
  'Verdana',
  'Tahoma',
  'Trebuchet MS',
  'Courier New',
];

// The stored font-family is often a STACK ("Arial, Helvetica, sans-serif"); take
// the first family so the select can reflect the current font.
const currentFamily = computed(() => {
  // eslint-disable-next-line no-unused-expressions
  props.revision;
  const raw = (
    props.property?.getValue?.({ noDefault: true }) ?? ''
  ).toString();
  return raw.split(',')[0].trim().replace(/['"]/g, '');
});

// Match the current family to a known option (case-insensitive). If the element
// uses a font outside our list, surface it as an extra option so the select still
// shows the real current value instead of going blank.
const matched = computed(() =>
  FONTS.find(f => f.toLowerCase() === currentFamily.value.toLowerCase())
);
const options = computed(() =>
  !currentFamily.value || matched.value
    ? FONTS
    : [currentFamily.value, ...FONTS]
);
const choices = computed(() =>
  options.value.map(font => ({ value: font, label: font }))
);
const selected = computed(() => matched.value ?? currentFamily.value);

const onChange = value => {
  emit('change', props.property, value);
};
</script>

<template>
  <ChoiceSelect
    :model-value="selected"
    :options="choices"
    :aria-label="t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.PROPS.TEXT.FONT_FAMILY')"
    :disabled="!property"
    class="w-full"
    @change="onChange"
  />
</template>
