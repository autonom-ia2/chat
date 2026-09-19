<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { NS, statusKey, reasonKey, displayStatusLabel } from './presentation';

const props = defineProps({
  record: { type: Object, required: true },
  campaign: Boolean,
});

const { t, te } = useI18n();
const key = computed(() => statusKey(props.record, props.campaign));

const VISUALS = {
  pending: ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-clock'],
  sent: ['bg-n-blue-3 text-n-blue-11', 'i-lucide-send'],
  delivered: ['bg-n-teal-3 text-n-teal-11', 'i-lucide-circle-check'],
  accepted_service: ['bg-n-teal-3 text-n-teal-11', 'i-lucide-circle-check'],
  acceptance_recorded: ['bg-n-blue-3 text-n-blue-11', 'i-lucide-circle-check'],
  opened: ['bg-n-blue-3 text-n-blue-11', 'i-lucide-mail-open'],
  clicked: ['bg-n-blue-3 text-n-blue-11', 'i-lucide-mouse-pointer-click'],
  temporary: ['bg-n-amber-3 text-n-amber-11', 'i-lucide-refresh-cw'],
  permanent: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-circle-x'],
  nonexistent: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-mail-x'],
  failed: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-circle-x'],
  complained: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-shield-alert'],
  invalid: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-mail-x'],
  review: ['bg-n-amber-3 text-n-amber-11', 'i-lucide-circle-help'],
  attention: ['bg-n-amber-3 text-n-amber-11', 'i-lucide-circle-alert'],
  high_risk: ['bg-n-ruby-3 text-n-ruby-11', 'i-lucide-shield-alert'],
  paused: ['bg-n-amber-3 text-n-amber-11', 'i-lucide-shield-alert'],
  manual: ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-pause'],
  suppressed: ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-shield-check'],
  protected: ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-shield-check'],
  unsubscribed: ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-user-minus'],
  healthy: ['bg-n-teal-3 text-n-teal-11', 'i-lucide-circle-check'],
  ready: ['bg-n-teal-3 text-n-teal-11', 'i-lucide-circle-check'],
};

const visual = computed(
  () => VISUALS[key.value] || ['bg-n-alpha-2 text-n-slate-11', 'i-lucide-info']
);
const label = computed(() =>
  key.value === 'delivered'
    ? te('CHAT_LIST.DELIVERED')
      ? t('CHAT_LIST.DELIVERED')
      : t('CAMPAIGN_MANAGEMENT.KPIS.DELIVERED')
    : displayStatusLabel(t, key.value)
);

const hint = computed(() =>
  t(
    `${NS}.REASON.${reasonKey(
      props.record.suppression_reason ||
        props.record.reason_code ||
        props.record.pause_reason ||
        props.record.preflight_reason
    )}`
  )
);
</script>

<template>
  <span
    data-email-status-badge
    class="inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
    :class="visual[0]"
    :title="hint"
    tabindex="0"
  >
    <Icon :icon="visual[1]" class="size-3.5 shrink-0" />
    {{ label }}
  </span>
</template>
