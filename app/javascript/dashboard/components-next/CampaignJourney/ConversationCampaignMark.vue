<script setup>
import { BULLET } from 'dashboard/components-next/CampaignJourney/textMarks';
// Top of the conversation (#1002, PRD D20, §6.11): the mark of the campaign that opened the
// conversation — its first campaign mark, or the origin when it has no campaign mark.
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  buildCrmOrigin,
  CAMPAIGN_MARK_SOURCES,
  useCrmOrigin,
} from 'dashboard/routes/dashboard/crm/composables/useCrmOrigin';

const props = defineProps({
  // additional_attributes of the conversation (campaign / campaign_touches).
  attributes: { type: Object, default: () => ({}) },
});

const { humanizedOriginLabel } = useCrmOrigin();

const mark = computed(() => {
  const { campaign_touches: touches, campaign } = props.attributes || {};
  const list = Array.isArray(touches) ? touches : [];
  const campaignMark = list.find(touch =>
    CAMPAIGN_MARK_SOURCES.includes(touch?.source)
  );
  return buildCrmOrigin(campaignMark || campaign || list[0]);
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <span
    v-if="mark"
    class="inline-flex min-w-0 items-center gap-1 text-n-teal-11"
    data-test-id="conversation-campaign-mark"
  >
    <span class="text-n-slate-11">{{ BULLET }}</span>
    <Icon :icon="mark.icon" class="size-3 shrink-0" />
    <span class="truncate">{{ humanizedOriginLabel(mark) }}</span>
  </span>
</template>
