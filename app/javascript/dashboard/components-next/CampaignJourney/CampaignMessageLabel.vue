<script setup>
// Campaign label above a message sent by a campaign (#1002, PRD D20, §6.11, P2).
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { campaignRefFor, useCampaignNames } from './useCampaignNames';

const props = defineProps({
  // Camel-cased additional attributes of the message.
  additionalAttributes: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const { request, nameFor } = useCampaignNames();
const campaignRef = computed(() => campaignRefFor(props.additionalAttributes));
const name = computed(() => (campaignRef.value ? nameFor(campaignRef.value) : ''));

watch(campaignRef, value => value && request(value), { immediate: true });
</script>

<template>
  <span
    v-if="name"
    class="inline-flex max-w-full items-center gap-1 rounded-md bg-n-teal-3 px-1.5 py-0.5 text-[11px] font-medium leading-4 text-n-teal-11"
    data-test-id="campaign-message-label"
  >
    <Icon icon="i-lucide-send" class="size-3 shrink-0" />
    <span class="truncate">
      {{ t('CRM_KANBAN.ORIGIN_JOURNEY.CAMPAIGN_MESSAGE', { name }) }}
    </span>
  </span>
</template>
