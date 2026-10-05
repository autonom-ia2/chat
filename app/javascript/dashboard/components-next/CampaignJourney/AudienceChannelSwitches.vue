<script setup>
// "Por onde dá para falar com essas pessoas" (#993, PRD §6.6-2, D13, J5, J6). Channels are
// on by what the spreadsheet has; one can be switched off. A channel without data shows
// off with "sem dados" and cannot be switched on.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import JourneySwitch from './JourneySwitch.vue';
import { channelSwitches } from './audienceReview';

const props = defineProps({
  channels: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.CHANNELS';
const { t, n } = useI18n();

const LABELS = { email: 'EMAIL', whatsapp: 'WHATSAPP' };
const NO_DATA_HINTS = { email: 'NO_EMAIL_HINT', whatsapp: 'NO_PHONE_HINT' };

const switches = computed(() => channelSwitches(props.channels));
const withoutData = computed(() =>
  switches.value.filter(item => !item.hasData)
);

const label = item => {
  const channel = t(`${NS}.${LABELS[item.channel]}`);
  return item.hasData
    ? t(`${NS}.COUNT`, { channel, count: n(item.count) })
    : t(`${NS}.NO_DATA`, { channel });
};
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak p-4"
    data-test="audience-channels"
  >
    <div>
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.TITLE`) }}
      </h2>
      <p class="m-0 mt-1 text-xs text-n-slate-11">{{ t(`${NS}.HINT`) }}</p>
    </div>
    <div class="flex flex-wrap gap-2">
      <JourneySwitch
        v-for="item in switches"
        :key="item.channel"
        :data-channel="item.channel"
        :checked="item.enabled"
        :disabled="disabled || !item.hasData"
        :label="label(item)"
        @toggle="emit('toggle', item.channel, !item.enabled)"
      />
    </div>
    <p
      v-for="item in withoutData"
      :key="item.channel"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t(`${NS}.${NO_DATA_HINTS[item.channel]}`) }}
    </p>
  </section>
</template>
