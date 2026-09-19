<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import { useAutonomiaCopilotStore } from 'dashboard/store/modules/autonomiaCopilot';

import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import ToggleCopilotAssistant from 'dashboard/components-next/copilot/ToggleCopilotAssistant.vue';
import CopilotInput from 'dashboard/components-next/copilot/CopilotInput.vue';
import CopilotAgentMessage from 'dashboard/components-next/copilot/CopilotAgentMessage.vue';
import CopilotAssistantMessage from 'dashboard/components-next/copilot/CopilotAssistantMessage.vue';
import CopilotLoader from 'dashboard/components-next/copilot/CopilotLoader.vue';

// V2.3 — "Copiloto Autonom.ia" chat widget. Reuses the Captain widget's presentational pieces
// (header / input / message bubbles / assistant selector) but is powered by OUR internal/both
// agents, gated by the kanban + copilot flags, with its own uiSetting keys. The drawer TITLE is
// the SELECTED AGENT'S NAME. Independent of Captain (works whether or not captain_integration is on).
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const globalConfig = useMapGetter('globalConfig/get');
const currentChat = useMapGetter('getSelectedChat');
const { width: windowWidth } = useWindowSize();

const store = useAutonomiaCopilotStore();
const { messages } = store;

const agents = ref([]);
const selectedAgentId = ref(null);
const isSending = ref(false);
const chatContainer = ref(null);

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const isEnabled = computed(
  () =>
    globalConfig.value?.crmKanbanEnabled === true &&
    globalConfig.value?.crmCopilotEnabled === true
);

const isPanelOpen = computed(
  () => uiSettings.value.is_autonomia_copilot_panel_open === true
);

const conversationDisplayId = computed(() => currentChat.value?.id);

// Só DENTRO de uma conversa: o copiloto agora é acessado pelo switch da conversa (SidepanelSwitch),
// não mais por um botão flutuante global.
const showPanel = computed(
  () => isEnabled.value && isPanelOpen.value && !!conversationDisplayId.value
);

const hasAgents = computed(() => agents.value.length > 0);
const hasMessages = computed(() => messages.length > 0);

const activeAgent = computed(() => {
  const preferred = agents.value.find(a => a.id === selectedAgentId.value);
  return preferred || agents.value[0] || null;
});

const panelTitle = computed(
  () => activeAgent.value?.name || t('AUTONOMIA_COPILOT.TITLE')
);

const headerButtons = computed(() => {
  if (!hasMessages.value) return [];
  return [
    {
      key: 'reset',
      icon: 'i-lucide-refresh-ccw',
      tooltip: t('AUTONOMIA_COPILOT.RESET'),
    },
  ];
});

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const closePanel = () => {
  // Fechar o copiloto volta ao painel de contato da conversa (não deixa o lado direito vazio).
  updateUISettings({
    is_autonomia_copilot_panel_open: false,
    is_contact_sidebar_open: true,
  });
};

const handleClickOutside = () => {
  if (isSmallScreen.value && isPanelOpen.value) closePanel();
};

const handleHeaderAction = action => {
  if (action === 'reset') store.reset();
};

// Default agent = the inbox's linked agent when it is internal/both, else the first agent.
// The remembered preference wins when still valid.
const resolveDefaultAgent = () => {
  const preferred = uiSettings.value.preferred_autonomia_copilot_agent_id;
  if (preferred && agents.value.some(a => a.id === preferred)) {
    selectedAgentId.value = preferred;
    return;
  }
  selectedAgentId.value = agents.value[0]?.id ?? null;
};

const setAgent = async agent => {
  selectedAgentId.value = agent.id;
  store.reset();
  await updateUISettings({ preferred_autonomia_copilot_agent_id: agent.id });
};

const fetchAgents = async () => {
  if (!conversationDisplayId.value) {
    agents.value = [];
    return;
  }
  try {
    const { data } = await AutonomiaCopilotAPI.listAgents(
      conversationDisplayId.value
    );
    agents.value = data.agents || [];
    resolveDefaultAgent();
  } catch {
    agents.value = [];
  }
};

const requestReply = async (requestConversation, message) => {
  try {
    const { data } = await AutonomiaCopilotAPI.chat(requestConversation, {
      agentId: activeAgent.value.id,
      message,
      history: store.toHistory(),
    });
    if (conversationDisplayId.value !== requestConversation) return;
    if (data.available && data.text) {
      store.addAssistantMessage({
        content: data.text,
        replySuggestion: data.reply_suggestion,
      });
    } else {
      store.addAssistantMessage({ content: '' });
      useAlert(t('AUTONOMIA_COPILOT.UNAVAILABLE'));
    }
  } catch {
    if (conversationDisplayId.value !== requestConversation) return;
    store.addAssistantMessage({ content: '' });
    useAlert(t('AUTONOMIA_COPILOT.ERROR'));
  } finally {
    // isSending is a single global flag (one request at a time) — always clear it,
    // even if the conversation changed mid-flight, so the new conversation isn't stuck.
    isSending.value = false;
  }
};

// CopilotInput clears the field only when this returns true. Accept = the question is in the
// thread, so return right away and let the reply load behind the loader; false keeps the text.
const sendMessage = message => {
  if (isSending.value || !activeAgent.value || !conversationDisplayId.value) {
    return false;
  }
  // Pin the conversation this request belongs to. If the agent navigates to
  // another conversation before the response lands, the late reply must NOT be
  // appended into the now-current conversation's thread (cross-conversation leak).
  const requestConversation = conversationDisplayId.value;
  store.addUserMessage(message);
  isSending.value = true;
  requestReply(requestConversation, message);
  return true;
};

watch(showPanel, opened => {
  if (opened) fetchAgents();
});

// Reset on ANY conversation change (even with the panel closed) so a thread from
// conversation A never lingers — or rides as `history` — when you later open the
// copilot on conversation B. Same-conversation close/reopen keeps its thread.
watch(conversationDisplayId, () => {
  store.reset();
  if (showPanel.value) fetchAgents();
});

watch(
  () => messages.length,
  () => scrollToBottom()
);

onMounted(() => {
  if (showPanel.value) fetchAgents();
});
</script>

<template>
  <div
    v-if="showPanel"
    v-on-click-outside="handleClickOutside"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none flex"
  >
    <div class="flex flex-col h-full text-sm leading-6 tracking-tight w-full">
      <SidebarActionsHeader
        :title="panelTitle"
        :buttons="headerButtons"
        @click="handleHeaderAction"
        @close="closePanel"
      />

      <div
        ref="chatContainer"
        class="flex-1 flex px-4 py-4 overflow-y-auto items-start"
      >
        <div v-if="hasMessages" class="space-y-6 flex-1 flex flex-col w-full">
          <template v-for="(item, index) in messages" :key="item.id">
            <CopilotAgentMessage
              v-if="item.message_type === 'user'"
              :message="item.message"
            />
            <CopilotAssistantMessage
              v-else
              :message="item.message"
              :is-last-message="index === messages.length - 1"
            />
          </template>
          <CopilotLoader v-if="isSending" />
        </div>
        <div v-else class="flex-1 flex flex-col gap-2 px-2 py-4">
          <h3 class="text-base font-medium text-n-slate-12 leading-8">
            {{ panelTitle }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-6">
            {{
              hasAgents
                ? $t('AUTONOMIA_COPILOT.KICK_OFF')
                : $t('AUTONOMIA_COPILOT.NO_AGENTS')
            }}
          </p>
        </div>
      </div>

      <div class="mx-3 mt-px mb-2">
        <div class="flex items-center gap-2 justify-between w-full mb-1">
          <ToggleCopilotAssistant
            v-if="agents.length > 1 && activeAgent"
            :assistants="agents"
            :active-assistant="activeAgent"
            @set-assistant="setAgent"
          />
          <div v-else />
        </div>
        <CopilotInput
          v-if="hasAgents"
          class="mb-1 w-full"
          @send="sendMessage"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>
