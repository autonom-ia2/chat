<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import LabelItem from 'dashboard/components-next/label/LabelItem.vue';

// Quem só lê (#1800) vê um resumo da conversa, sem nenhum controle. Linha vazia não aparece, menos "Quem atende",
// que é o que a pessoa vem procurar.
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');
const { activeLabels } = useConversationLabels();

const assignee = computed(() => currentChat.value?.meta?.assignee);
const team = computed(() => currentChat.value?.meta?.team);
const priorityName = computed(
  () =>
    ({
      urgent: t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
      high: t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
      medium: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
      low: t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
    })[currentChat.value?.priority]
);
</script>

<template>
  <dl class="flex flex-col m-0 text-sm" data-acoes-so-leitura>
    <div
      class="flex items-center justify-between gap-3 py-2 border-b border-n-weak last:border-b-0"
    >
      <dt class="text-n-slate-11">
        {{ $t('CONVERSATION.SO_LEITURA.QUEM_ATENDE') }}
      </dt>
      <dd
        class="flex items-center min-w-0 gap-2 m-0 font-medium text-n-slate-12"
      >
        <template v-if="assignee">
          <Avatar
            :name="assignee.name"
            :src="assignee.thumbnail || ''"
            :size="20"
            rounded-full
          />
          <span class="truncate">{{ assignee.name }}</span>
        </template>
        <span v-else class="font-normal text-n-slate-11">
          {{ $t('CONVERSATION.SO_LEITURA.NINGUEM') }}
        </span>
      </dd>
    </div>
    <div
      v-if="team"
      class="flex items-center justify-between gap-3 py-2 border-b border-n-weak last:border-b-0"
    >
      <dt class="text-n-slate-11">{{ $t('CONVERSATION.SO_LEITURA.TIME') }}</dt>
      <dd class="m-0 font-medium truncate text-n-slate-12">{{ team.name }}</dd>
    </div>
    <div
      v-if="priorityName"
      class="flex items-center justify-between gap-3 py-2 border-b border-n-weak last:border-b-0"
    >
      <dt class="text-n-slate-11">{{ $t('CONVERSATION.PRIORITY.TITLE') }}</dt>
      <dd class="m-0 font-medium text-n-slate-12">{{ priorityName }}</dd>
    </div>
    <div
      v-if="activeLabels.length"
      class="flex flex-col gap-2 py-2 border-b border-n-weak last:border-b-0"
    >
      <dt class="text-n-slate-11">
        {{ $t('CONVERSATION.SO_LEITURA.ETIQUETAS') }}
      </dt>
      <dd class="flex flex-wrap gap-2 m-0">
        <LabelItem
          v-for="label in activeLabels"
          :key="label.id"
          :label="label"
          read-only
        />
      </dd>
    </div>
  </dl>
</template>
