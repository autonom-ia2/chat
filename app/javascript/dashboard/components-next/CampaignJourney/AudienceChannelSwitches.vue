<script setup>
import { formatNumber } from 'dashboard/helper/localeTag';
// "Por onde dá para falar com essas pessoas" (#993, PRD §6.6-2, D13, J5, J6). Channels are
// on by what the spreadsheet has; one can be switched off. A channel without data shows
// off with "sem dados" and cannot be switched on.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LabeledSwitch from 'dashboard/components-next/switch/LabeledSwitch.vue';
import { channelSwitches } from './audienceReview';

const props = defineProps({
  channels: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
  // #1004: an SMS inbox is connected in the account (else the SMS badge is locked, "sem caixa").
  smsInbox: { type: Boolean, default: true },
});

const emit = defineEmits(['toggle']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.CHANNELS';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);

const LABELS = { email: 'EMAIL', whatsapp: 'WHATSAPP', sms: 'SMS' };
const NO_DATA_HINTS = {
  email: 'NO_EMAIL_HINT',
  whatsapp: 'NO_PHONE_HINT',
  sms: 'NO_PHONE_HINT',
};

const switches = computed(() =>
  channelSwitches(props.channels, { smsInbox: props.smsInbox })
);
const hints = computed(() =>
  switches.value.flatMap(item => {
    if (!item.hasInbox)
      return [{ channel: item.channel, key: 'NO_INBOX_HINT' }];
    if (!item.hasData) {
      return [{ channel: item.channel, key: NO_DATA_HINTS[item.channel] }];
    }
    return [];
  })
);

const label = item => {
  const channel = t(`${NS}.${LABELS[item.channel]}`);
  if (!item.hasInbox) return t(`${NS}.NO_INBOX`, { channel });
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
      <LabeledSwitch
        v-for="item in switches"
        :key="item.channel"
        :data-channel="item.channel"
        :checked="item.enabled"
        :disabled="disabled || !item.hasData || !item.hasInbox"
        :label="label(item)"
        @toggle="emit('toggle', item.channel, !item.enabled)"
      />
    </div>
    <p
      v-for="hint in hints"
      :key="hint.channel"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t(`${NS}.${hint.key}`) }}
    </p>
  </section>
</template>
