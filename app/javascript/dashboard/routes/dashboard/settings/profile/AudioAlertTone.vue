<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import * as Sentry from '@sentry/vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  value: {
    type: String,
    required: true,
    validator: value =>
      ['ding', 'bell', 'chime', 'magic', 'ping'].includes(value),
  },
  label: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['change']);

const alertTones = computed(() => [
  {
    value: 'ding',
    label: 'Ding',
  },
  {
    value: 'bell',
    label: 'Bell',
  },
  {
    value: 'chime',
    label: 'Chime',
  },
  {
    value: 'magic',
    label: 'Magic',
  },
  {
    value: 'ping',
    label: 'Ping',
  },
]);

const selectedValue = computed({
  get: () => props.value,
  set: value => {
    emit('change', value);
  },
});

const audio = new Audio();

const playAudio = async () => {
  try {
    // Has great support https://caniuse.com/mdn-api_htmlaudioelement
    audio.src = `/audio/dashboard/${selectedValue.value}.mp3`;
    await audio.play();
  } catch (error) {
    Sentry.captureException(error);
  }
};
</script>

<template>
  <div class="flex items-end gap-2">
    <div class="flex flex-col flex-grow gap-1">
      <span class="text-sm font-medium text-n-slate-12">{{ label }}</span>
      <ChoiceSelect
        v-model="selectedValue"
        :options="alertTones"
        :aria-label="label"
      />
    </div>
    <button
      v-tooltip.top="
        $t('PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.PLAY')
      "
      class="border-0 shadow-sm outline-none flex justify-center items-center appearance-none rounded-xl ring-n-weak ring-1 ring-inset focus:ring-2 focus:ring-inset focus:ring-n-brand flex-shrink-0 size-11"
      @click="playAudio"
    >
      <Icon icon="i-lucide-volume-2" />
    </button>
  </div>
</template>
