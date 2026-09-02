<script setup>
import { computed, ref } from 'vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MessagePreview from 'dashboard/components-next/Conversation/ConversationCard/MessagePreview.vue';
import CardLabels from 'dashboard/components-next/Conversation/ConversationCard/CardLabels.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/ConversationCard/SLACardLabel.vue';
import CrmConversationStageChip from 'dashboard/components-next/Conversation/ConversationCard/CrmConversationStageChip.vue';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { useCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
  contact: {
    type: Object,
    required: true,
  },
  hasLabels: {
    type: Boolean,
    default: false,
  },
});

const { canViewCrm } = useCrmPermissions();
const crmChipEnabled = computed(
  () => canViewCrm.value && window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
);
const crmStage = useCrmConversationStage(
  computed(() => (crmChipEnabled.value ? props.conversation?.id : null))
);
const hasCrmStage = computed(() => !!crmStage.value?.stage_name);
// Labels row is rendered when there are labels (upstream) or a CRM stage chip (fork).
const hasMetaChips = computed(() => props.hasLabels || hasCrmStage.value);

const slaCardLabelRef = ref(null);

const lastNonActivityMessage = computed(() =>
  useSnakeCase(props.conversation.lastNonActivityMessage ?? {}, { deep: true })
);

const assignee = computed(() => {
  const { meta: { assignee: agent = {} } = {} } = props.conversation;
  return {
    name: agent.name ?? agent.availableName,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus,
  };
});

const unreadMessagesCount = computed(() => {
  const { unreadCount } = props.conversation;
  return unreadCount;
});

const hasSlaThreshold = computed(() => {
  return (
    !props.contact?.blocked &&
    slaCardLabelRef.value?.hasSlaThreshold &&
    props.conversation?.appliedSla?.id
  );
});

defineExpose({
  hasSlaThreshold,
});
</script>

<template>
  <div class="flex flex-col w-full gap-1">
    <div class="flex items-center justify-between w-full gap-2 py-1 h-7">
      <MessagePreview
        :message="lastNonActivityMessage"
        class="flex-1 min-w-0"
        :class="unreadMessagesCount > 0 ? 'text-n-slate-12' : 'text-n-slate-11'"
      />

      <div
        v-if="unreadMessagesCount > 0"
        class="inline-flex items-center justify-center flex-shrink-0 rounded-full size-5 bg-n-brand"
      >
        <span class="text-xs font-semibold text-white">
          {{ unreadMessagesCount }}
        </span>
      </div>
    </div>

    <div
      class="grid items-center gap-2.5 h-7"
      :class="
        hasSlaThreshold && hasMetaChips
          ? 'grid-cols-[auto_auto_1fr_20px]'
          : 'grid-cols-[1fr_20px]'
      "
    >
      <SLACardLabel
        v-show="hasSlaThreshold"
        ref="slaCardLabelRef"
        :conversation="conversation"
      />
      <div
        v-if="hasSlaThreshold && hasMetaChips"
        class="w-px h-3 bg-n-slate-4"
      />
      <div
        v-if="hasMetaChips"
        class="flex items-center gap-1.5 overflow-hidden min-w-0"
      >
        <CrmConversationStageChip
          v-if="hasCrmStage"
          :conversation-id="conversation.id"
        />
        <CardLabels
          v-if="hasLabels"
          :conversation-labels="conversation.labels"
          :account-labels="accountLabels"
          class="min-w-0"
        />
      </div>
      <Avatar
        v-if="assignee.name"
        :name="assignee.name"
        :src="assignee.thumbnail"
        :size="20"
        :status="assignee.status"
        rounded-full
      />
    </div>
  </div>
</template>
