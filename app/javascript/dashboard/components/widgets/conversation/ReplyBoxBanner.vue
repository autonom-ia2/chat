<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';

import Banner from 'dashboard/components/ui/Banner.vue';

// #2067: a faixa "Esta conversa não está atribuída a você… Atribuir a mim" saiu. Quem
// escreve fica com a conversa ao enviar (FicarComAConversa, na caixa de resposta).
const store = useStore();
const { t } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');

const assignedAgent = computed({
  get() {
    return currentChat.value?.meta?.assignee;
  },
  set(agent) {
    const agentId = agent ? agent.id : null;
    store.dispatch('setCurrentChatAssignee', {
      conversationId: currentChat.value?.id,
      assignee: agent,
      assigneeType: agent ? 'User' : null,
    });
    store.dispatch('assignAgent', {
      conversationId: currentChat.value?.id,
      agentId,
    });
  },
});

const isUnassigned = computed(() => !assignedAgent.value);
const isAssignedToOtherAgent = computed(
  () => assignedAgent.value?.id !== currentUser.value?.id
);

const isPendingConversation = computed(
  () => currentChat.value?.status === wootConstants.STATUS_TYPE.PENDING
);

const isAgentBotOwned = computed(
  () => currentChat.value?.meta?.assignee_type === 'AgentBot'
);

const showBotHandoffBanner = computed(() => {
  return isPendingConversation.value && isAgentBotOwned.value;
});

const botAssigneeName = computed(() => {
  if (isAgentBotOwned.value && assignedAgent.value?.name) {
    return assignedAgent.value.name;
  }

  return t('CONVERSATION.BOT_HANDOFF_FALLBACK_ASSIGNEE');
});

const selfAssignConversation = async () => {
  const { avatar_url, ...rest } = currentUser.value || {};
  assignedAgent.value = { ...rest, thumbnail: avatar_url };
};

const needsAssignmentToCurrentUser = computed(() => {
  return isUnassigned.value || isAssignedToOtherAgent.value;
});

const reopenConversation = async () => {
  await store.dispatch('toggleStatus', {
    conversationId: currentChat.value?.id,
    status: 'open',
  });
};

const onClickBotHandoff = async () => {
  try {
    const shouldAssignToCurrentUser =
      isAgentBotOwned.value || needsAssignmentToCurrentUser.value;

    await reopenConversation();

    if (shouldAssignToCurrentUser) {
      await selfAssignConversation();
    }

    useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
  }
};
</script>

<template>
  <Banner
    v-show="showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="
      $t('CONVERSATION.BOT_HANDOFF_MESSAGE', {
        assigneeName: botAssigneeName,
      })
    "
    has-action-button
    :action-button-label="$t('CONVERSATION.BOT_HANDOFF_ACTION')"
    @primary-action="onClickBotHandoff"
  />
</template>
