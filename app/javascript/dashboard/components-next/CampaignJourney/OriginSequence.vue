<script setup>
// Every origin and campaign mark in order (#1002, PRD §6.7 and §6.11): "Link: Feira 2026 →
// Campanha e-mail: Novidades de outubro → Campanha WhatsApp: …". Used by the CRM card
// drawer and the contact panel of the conversation.
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useCrmOrigin } from 'dashboard/routes/dashboard/crm/composables/useCrmOrigin';

defineProps({
  // Origins built by useCrmOrigin (originFromCampaign), first touch first.
  origins: { type: Array, default: () => [] },
});

const { humanizedOriginLabel } = useCrmOrigin();
</script>

<template>
  <ol class="flex min-w-0 flex-col gap-1" data-test-id="origin-sequence">
    <li
      v-for="(origin, index) in origins"
      :key="`${origin.sourceId || origin.source}-${index}`"
      class="flex min-w-0 items-center gap-1.5 text-xs text-n-slate-12"
    >
      <Icon :icon="origin.icon" class="size-3.5 shrink-0 text-n-teal-11" />
      <span class="truncate" :title="origin.sourceUrl || undefined">
        {{ humanizedOriginLabel(origin) }}
      </span>
    </li>
  </ol>
</template>
