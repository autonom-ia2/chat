<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import LabelItem from 'dashboard/components-next/label/LabelItem.vue';
import ContactDetailsItem from './ContactDetailsItem.vue';

// Quem só lê (#1800) vê responsável, time, prioridade e etiquetas, sem mexer.
const currentChat = useMapGetter('getSelectedChat');
const { activeLabels } = useConversationLabels();

const assignee = computed(() => currentChat.value?.meta?.assignee);
const team = computed(() => currentChat.value?.meta?.team);
const priorityKey = computed(() =>
  currentChat.value?.priority
    ? currentChat.value.priority.toUpperCase()
    : 'NONE'
);
</script>

<template>
  <div class="flex flex-col gap-3" data-acoes-so-leitura>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.ASSIGNEE_LABEL')"
      />
      <div class="flex items-center gap-2 text-sm text-n-slate-12">
        <template v-if="assignee">
          <Avatar
            :name="assignee.name"
            :src="assignee.thumbnail || ''"
            :size="20"
            rounded-full
          />
          <span class="truncate">{{ assignee.name }}</span>
        </template>
        <span v-else class="text-n-slate-11">
          {{ $t('CONVERSATION.SO_LEITURA.NINGUEM') }}
        </span>
      </div>
    </div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.TEAM_LABEL')"
      />
      <span
        class="text-sm"
        :class="team ? 'text-n-slate-12' : 'text-n-slate-11'"
      >
        {{ team ? team.name : $t('CONVERSATION.SO_LEITURA.NINGUEM') }}
      </span>
    </div>
    <div>
      <ContactDetailsItem compact :title="$t('CONVERSATION.PRIORITY.TITLE')" />
      <span class="text-sm text-n-slate-12">
        {{ $t(`CONVERSATION.PRIORITY.OPTIONS.${priorityKey}`) }}
      </span>
    </div>
    <div>
      <ContactDetailsItem
        compact
        :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS')"
      />
      <div v-if="activeLabels.length" class="flex flex-wrap gap-2">
        <LabelItem
          v-for="label in activeLabels"
          :key="label.id"
          :label="label"
          read-only
        />
      </div>
      <span v-else class="text-sm text-n-slate-11">
        {{ $t('CONVERSATION.SO_LEITURA.SEM_ETIQUETAS') }}
      </span>
    </div>
  </div>
</template>
