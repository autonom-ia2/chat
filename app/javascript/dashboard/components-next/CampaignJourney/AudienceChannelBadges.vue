<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  // [{ channel: 'email' | 'whatsapp', count }], see audienceRows.js
  badges: { type: Array, default: () => [] },
});

const { t, n } = useI18n();

const ICONS = { email: 'i-lucide-mail', whatsapp: 'i-lucide-message-circle' };
const LABELS = { email: 'EMAIL', whatsapp: 'WHATSAPP' };
</script>

<template>
  <ul v-if="badges.length" class="m-0 flex list-none flex-wrap gap-1.5 p-0">
    <li
      v-for="badge in badges"
      :key="badge.channel"
      :data-badge="badge.channel"
      class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium"
      :class="
        badge.channel === 'email'
          ? 'bg-n-blue-3 text-n-blue-11'
          : 'bg-n-teal-3 text-n-teal-11'
      "
    >
      <span :class="ICONS[badge.channel]" class="size-3.5" aria-hidden="true" />
      {{
        t('CAMPAIGN_JOURNEY.AUDIENCES.BADGE', {
          channel: t(`CAMPAIGN_JOURNEY.AUDIENCES.BADGES.${LABELS[badge.channel]}`),
          count: n(badge.count),
        })
      }}
    </li>
  </ul>
  <span v-else class="text-xs text-n-slate-11" data-badge="none">
    {{ t('CAMPAIGN_JOURNEY.AUDIENCES.NO_CHANNELS') }}
  </span>
</template>
