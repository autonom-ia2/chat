<script setup>
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

defineProps({
  placeholders: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['insert']);

const { t, te } = useI18n();
const label = key => {
  const translation = `CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.PERSONALIZATION.${key}`;
  return te(translation) ? t(translation) : key.split('_').join(' ');
};

const chipLabel = key => `{{ ${key} }}`;

const onChipClick = async key => {
  await copyTextToClipboard(chipLabel(key));
  useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.COPY_SUCCESS'));
  emit('insert', key);
};
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="key in placeholders"
      :key="key"
      type="button"
      class="inline-flex items-center gap-1 min-h-11 px-3 py-2 text-sm rounded-xl text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
      @click="onChipClick(key)"
    >
      <span class="i-lucide-copy size-3 text-n-slate-11" />
      {{ label(key) }}
    </button>
  </div>
</template>
