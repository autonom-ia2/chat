<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { formatTime } from '@chatwoot/utils';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  record: {
    type: Object,
    required: true,
  },
  // The agent panel has a tighter mobile card than the reports drawer. Keep
  // the reports rendering unchanged and opt into the responsive presentation
  // only from the F4 consumer.
  agentPanel: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const route = useRoute();

const conversation = computed(() => props.record.conversation || {});
const message = computed(() => props.record.message || {});
const isMessageRecord = computed(() => props.record.record_type === 'message');
const isEventBackedConversationRecord = computed(
  () => !isMessageRecord.value && !!props.record.event_name
);
const conversationDisplayId = computed(() => conversation.value.display_id);
const conversationNumber = computed(() => `#${conversationDisplayId.value}`);
const messageDirection = computed(() => message.value.message_type);
const isAgentPanel = computed(() => props.agentPanel);

const formatTimestamp = timestamp => {
  if (!timestamp) return '';

  return format(fromUnixTime(timestamp), 'dd MMM yyyy, h:mm a');
};

const compactTimestamp = timestamp => {
  if (!timestamp) return '';

  return shortTimestamp(dynamicTime(timestamp)).trim();
};

const metricValue = computed(() => {
  const value = props.record.metric_value;
  if (value === null || value === undefined) return '';

  return formatTime(value) || `${value}`;
});

const previewText = computed(() => {
  if (message.value.content) return message.value.content;
  if (conversation.value.last_message?.content) {
    return conversation.value.last_message.content;
  }

  return t('REPORT.DRILLDOWN.NO_MESSAGE_CONTENT');
});

const showPreview = computed(() => {
  return isMessageRecord.value || conversation.value.last_message;
});

const messageCreatedTooltip = computed(() =>
  t('REPORT.DRILLDOWN.MESSAGE_CREATED_AT', {
    time: formatTimestamp(message.value.created_at),
  })
);

const eventOccurredTooltip = computed(() =>
  t('REPORT.DRILLDOWN.EVENT_OCCURRED_AT', {
    time: formatTimestamp(props.record.occurred_at),
  })
);

const conversationStatusLabel = computed(() => {
  const status = String(conversation.value.status || '').toUpperCase();
  if (!status) return '';

  const knownStatuses = ['OPEN', 'PENDING', 'RESOLVED', 'SNOOZED'];
  const key = knownStatuses.includes(status) ? status : 'UNKNOWN';
  return t(`AGENTS.PANEL.REDESIGN_DRAWER.STATUS_${key}`);
});

const agentPanelTimestamp = computed(() => {
  if (isMessageRecord.value) return message.value.created_at;
  if (isEventBackedConversationRecord.value) return props.record.occurred_at;

  return conversation.value.last_activity_at;
});

const agentPanelTimestampTooltip = computed(() => {
  if (!agentPanelTimestamp.value) return '';
  if (isMessageRecord.value) return messageCreatedTooltip.value;
  if (isEventBackedConversationRecord.value) return eventOccurredTooltip.value;

  return `${t('AGENTS.PANEL.REDESIGN_DRAWER.LAST_ACTIVITY')} ${formatTimestamp(
    agentPanelTimestamp.value
  )}`;
});

const directionDetails = computed(() => {
  const direction = messageDirection.value;
  if (!direction) return null;

  const isIncoming = direction === 'incoming';
  return {
    icon: isIncoming ? 'i-lucide-arrow-down-left' : 'i-lucide-arrow-up-right',
    tooltip: isIncoming
      ? t('REPORT.DRILLDOWN.INCOMING_MESSAGE')
      : t('REPORT.DRILLDOWN.OUTGOING_MESSAGE'),
  };
});

const conversationPath = computed(() => {
  if (!conversationDisplayId.value) return '';

  const path = conversationUrl({
    accountId: route.params.accountId,
    id: conversationDisplayId.value,
  });
  const params =
    isMessageRecord.value && message.value.id
      ? { messageId: message.value.id }
      : null;

  return frontendURL(path, params);
});

const contactPath = computed(() => {
  if (!conversation.value.contact_id) return '';

  return frontendURL(
    `accounts/${route.params.accountId}/contacts/${conversation.value.contact_id}`
  );
});

const inboxPath = computed(() => {
  if (!conversation.value.inbox_id) return '';

  return frontendURL(
    `accounts/${route.params.accountId}/inbox/${conversation.value.inbox_id}`
  );
});

const agentPath = computed(() => {
  if (!conversation.value.assignee_id) return '';

  return frontendURL(
    `accounts/${route.params.accountId}/reports/agents/${conversation.value.assignee_id}`
  );
});

const metadataItems = computed(() => [
  {
    key: 'contact',
    icon: 'i-lucide-contact',
    label:
      conversation.value.contact_name || t('REPORT.DRILLDOWN.UNKNOWN_CONTACT'),
    path: contactPath.value,
  },
  {
    key: 'inbox',
    icon: 'i-lucide-inbox',
    label: conversation.value.inbox_name || t('REPORT.DRILLDOWN.UNKNOWN_INBOX'),
    path: inboxPath.value,
  },
  {
    key: 'agent',
    icon: 'i-lucide-user-round',
    label:
      conversation.value.assignee_name ||
      t('REPORT.DRILLDOWN.UNASSIGNED_AGENT'),
    path: agentPath.value,
  },
]);

const metadataAttributes = item => {
  if (!item.path) return {};

  return {
    href: item.path,
    target: '_blank',
    rel: 'noopener noreferrer',
  };
};

const metadataItemClass = item => [
  'flex min-w-0 items-center gap-1 text-n-slate-11',
  item.path ? 'group hover:text-n-blue-11 hover:underline' : '',
  isAgentPanel.value ? 'items-start whitespace-normal break-words' : '',
];

const metadataIconClass = item => [
  'size-3 shrink-0 text-n-slate-9',
  item.path ? 'group-hover:text-n-blue-11' : '',
];

const stopMetadataLinkClick = (event, item) => {
  if (item.path) {
    event.stopPropagation();
  }
};

const openInNewTab = url => {
  if (!url) return;

  window.open(url, '_blank', 'noopener,noreferrer');
};

const openRecord = () => {
  openInNewTab(conversationPath.value);
};
</script>

<template>
  <article
    role="link"
    tabindex="0"
    class="cursor-pointer rounded-md border border-n-weak bg-n-solid-2 p-3 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="openRecord"
    @keydown.enter.self.prevent="openRecord"
    @keydown.space.self.prevent="openRecord"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <div
          class="flex items-center gap-2 text-sm font-medium leading-5 text-n-slate-12"
        >
          <span>{{ conversationNumber }}</span>
          <span
            v-if="conversation.status"
            class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs capitalize text-n-slate-11"
          >
            {{ isAgentPanel ? conversationStatusLabel : conversation.status }}
          </span>
          <span
            v-if="directionDetails"
            v-tooltip.top="directionDetails.tooltip"
            :aria-label="directionDetails.tooltip"
            role="img"
            class="flex size-5 items-center justify-center rounded bg-n-alpha-2 text-n-slate-11"
          >
            <Icon
              :icon="directionDetails.icon"
              class="size-3"
              aria-hidden="true"
            />
          </span>
          <span
            v-if="metricValue"
            class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-11"
          >
            {{ metricValue }}
          </span>
        </div>
      </div>
      <div
        class="ms-2 flex shrink-0 items-center justify-end gap-1 text-end text-xs leading-4 text-n-slate-11"
      >
        <span
          v-if="isAgentPanel"
          v-tooltip.left="agentPanelTimestampTooltip"
          :title="agentPanelTimestampTooltip"
          class="whitespace-nowrap"
        >
          {{ compactTimestamp(agentPanelTimestamp) }}
          <span class="sr-only">{{ agentPanelTimestampTooltip }}</span>
        </span>
        <template v-else>
          <span
            v-if="isMessageRecord"
            v-tooltip.left="messageCreatedTooltip"
            :title="messageCreatedTooltip"
            class="whitespace-nowrap"
          >
            {{ compactTimestamp(message.created_at) }}
            <span class="sr-only">{{ messageCreatedTooltip }}</span>
          </span>
          <TimeAgo
            v-else
            :is-auto-refresh-enabled="false"
            :conversation-id="conversation.id"
            :last-activity-timestamp="conversation.last_activity_at"
            :created-at-timestamp="conversation.created_at"
            class="font-440 !text-xs !text-n-slate-11"
          />
          <span
            v-if="isEventBackedConversationRecord"
            v-tooltip.left="eventOccurredTooltip"
            :title="eventOccurredTooltip"
            class="whitespace-nowrap rounded bg-n-alpha-2 px-1 py-0.5 text-[11px] leading-4 text-n-slate-11"
          >
            {{ compactTimestamp(record.occurred_at) }}
            <span class="sr-only">{{ eventOccurredTooltip }}</span>
          </span>
        </template>
      </div>
    </div>

    <p
      v-if="showPreview"
      class="mt-2 line-clamp-1 text-sm leading-5 text-n-slate-12"
    >
      {{ previewText }}
    </p>

    <div
      class="mt-2 grid gap-2"
      :class="isAgentPanel ? 'grid-cols-1 sm:grid-cols-3' : 'grid-cols-3'"
    >
      <component
        :is="item.path ? 'a' : 'span'"
        v-for="item in metadataItems"
        :key="item.key"
        class="text-body-main"
        v-bind="metadataAttributes(item)"
        :class="metadataItemClass(item)"
        @click="stopMetadataLinkClick($event, item)"
      >
        <Icon :icon="item.icon" :class="metadataIconClass(item)" />
        <span :class="isAgentPanel ? 'break-words' : 'truncate'">
          {{ item.label }}
        </span>
      </component>
    </div>
  </article>
</template>
