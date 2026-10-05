<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { websiteReadiness } from './trackedLinkWebsite';

// Header of the selected origin. A website origin only says "ready" once the
// site is sending signals; otherwise it says what is still missing, so the top
// of the panel never contradicts the status shown below it.
const props = defineProps({
  link: { type: Object, required: true },
});
const { t } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const NEUTRAL = 'text-n-slate-11';
const STATES = {
  direct: { key: 'READY', icon: 'i-lucide-qr-code', tone: NEUTRAL },
  ready: { key: 'READY_WEBSITE', icon: 'i-lucide-globe', tone: NEUTRAL },
  waiting: { key: 'WEBSITE_WAITING', icon: 'i-lucide-globe', tone: NEUTRAL },
  needs_origins: {
    key: 'WEBSITE_NEEDS_ORIGINS',
    icon: 'i-lucide-globe',
    tone: 'text-n-amber-11',
  },
};

const stateName = computed(() =>
  props.link.usage === 'website' ? websiteReadiness(props.link) : 'direct'
);
const state = computed(() => STATES[stateName.value]);
</script>

<template>
  <div
    class="flex items-center gap-2 text-xs font-medium"
    :class="state.tone"
    :data-state="stateName"
  >
    <span class="size-4" :class="state.icon" />
    {{ t(`${NS}.${state.key}`) }}
  </div>
</template>
