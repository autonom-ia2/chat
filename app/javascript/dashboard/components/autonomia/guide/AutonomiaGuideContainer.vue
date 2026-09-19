<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { useAutonomiaGuideStore } from 'dashboard/store/modules/autonomiaGuide';
import { isGuideRoute } from 'dashboard/helper/guideRouteRegistry';
import { useGuideHighlight } from 'dashboard/store/modules/guideHighlight';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import CopilotInput from 'dashboard/components-next/copilot/CopilotInput.vue';
import CopilotAgentMessage from 'dashboard/components-next/copilot/CopilotAgentMessage.vue';
import CopilotAssistantMessage from 'dashboard/components-next/copilot/CopilotAssistantMessage.vue';
import CopilotLoader from 'dashboard/components-next/copilot/CopilotLoader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// V1 — global "Guia da Plataforma" widget. Reuses the copilot presentational pieces but is NOT
// conversation-scoped: a single global thread that guides the user (onboarding/support) and, when
// the backend returns a `navigation` target, offers a button that takes the user to that screen
// (validated against the guide route allow-list + the router + the route guards). Read-only.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const { uiSettings, updateUISettings } = useUISettings();
const currentAccount = useMapGetter('accounts/getAccount');
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// Guide routes that require an account feature flag — skipped (no button) when the feature is off,
// so the guide never offers an SLA screen that the backend gates with a 404.
const GUIDE_ROUTE_FEATURE = {
  crm_sla_index: FEATURE_FLAGS.SLA,
  sla_reports: FEATURE_FLAGS.SLA,
};
const { width: windowWidth } = useWindowSize();

const store = useAutonomiaGuideStore();
const { messages } = store;
const guideHighlight = useGuideHighlight();

const isSending = ref(false);
const chatContainer = ref(null);

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const isEnabled = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const isPanelOpen = computed(
  () => uiSettings.value.is_autonomia_guide_panel_open === true
);

const showPanel = computed(() => isEnabled.value && isPanelOpen.value);

const hasMessages = computed(() => messages.length > 0);

const suggestions = computed(() => [
  t('AUTONOMIA_GUIDE.SUGGESTIONS.KANBAN'),
  t('AUTONOMIA_GUIDE.SUGGESTIONS.WHATSAPP'),
  t('AUTONOMIA_GUIDE.SUGGESTIONS.REPORTS'),
]);

const headerButtons = computed(() => {
  if (!hasMessages.value) return [];
  return [
    {
      key: 'reset',
      icon: 'i-lucide-refresh-ccw',
      tooltip: t('AUTONOMIA_GUIDE.RESET'),
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
  updateUISettings({
    is_autonomia_guide_panel_open: false,
    is_contact_sidebar_open: false,
  });
};

const handleClickOutside = () => {
  if (isSmallScreen.value && isPanelOpen.value) closePanel();
};

const handleHeaderAction = action => {
  if (action === 'reset') store.reset();
};

// Resolve a backend `navigation` to a real router location, or null. Defense-in-depth: the route must
// be in the guide allow-list AND resolve cleanly (router.resolve THROWS on a missing required param,
// so routes needing ids we don't have — e.g. a specific inbox/conversation — return null and render
// NO button instead of a dead one). The route guards still enforce the user's permission on push.
const navLocation = nav => {
  if (!nav?.route_name || !isGuideRoute(nav.route_name)) return null;
  const requiredFeature = GUIDE_ROUTE_FEATURE[nav.route_name];
  if (
    requiredFeature &&
    !isFeatureEnabledonAccount.value(accountId.value, requiredFeature)
  ) {
    return null; // feature off → no button (backend would 404 the screen)
  }
  try {
    const target = accountScopedRoute(nav.route_name);
    const resolved = router.resolve(target);
    return resolved?.matched?.length ? target : null;
  } catch {
    return null; // unknown route or missing required param
  }
};

// Read-only — we never act, just move the user to the screen and (V2) highlight the element there.
const navigateTo = nav => {
  const target = navLocation(nav);
  if (!target) return;
  router.push(target);
  if (nav.highlight) {
    // Close the chat panel so the highlighted element is fully visible (the right-docked panel would
    // otherwise cover right-aligned action buttons). Trigger AFTER the close transition so the element
    // is at its final position. The thread is preserved — reopening the Guia shows it again.
    const anchor = nav.highlight;
    closePanel();
    setTimeout(() => guideHighlight.show(anchor), 320);
  } else if (isSmallScreen.value) {
    closePanel();
  }
};

const requestReply = async (requestAccount, message) => {
  try {
    const { data } = await AutonomiaGuideAPI.chat({
      message,
      history: store.toHistory(),
      routeContext: route.name,
    });
    if (accountId.value !== requestAccount) return;
    if (data.available && data.text) {
      store.addAssistantMessage({
        content: data.text,
        navigation: data.navigation || null,
      });
    } else {
      store.addAssistantMessage({ content: '' });
      useAlert(t('AUTONOMIA_GUIDE.UNAVAILABLE'));
    }
  } catch {
    if (accountId.value !== requestAccount) return;
    store.addAssistantMessage({ content: '' });
    useAlert(t('AUTONOMIA_GUIDE.ERROR'));
  } finally {
    isSending.value = false;
  }
};

// CopilotInput clears the field only when this returns true. Accept = the question is in the
// thread, so return right away and let the reply load behind the loader; false keeps the text.
const sendMessage = message => {
  if (isSending.value || !message?.trim()) return false;
  // Pin the account this request belongs to: if the user switches accounts before the reply lands,
  // the late response must NOT be appended into the now-current account's thread (cross-account leak).
  const requestAccount = accountId.value;
  store.addUserMessage(message);
  isSending.value = true;
  requestReply(requestAccount, message);
  return true;
};

watch(
  () => messages.length,
  () => scrollToBottom()
);

// The guide thread is a global module-level singleton; clear it when switching accounts so the
// previous account's conversation never lingers on screen for a different account/operator.
watch(accountId, () => store.reset());
</script>

<template>
  <div
    v-if="showPanel"
    v-on-click-outside="handleClickOutside"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none flex"
  >
    <div class="flex flex-col h-full text-sm leading-6 tracking-tight w-full">
      <SidebarActionsHeader
        :title="$t('AUTONOMIA_GUIDE.TITLE')"
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
            <div v-else class="flex flex-col gap-2 w-full">
              <CopilotAssistantMessage
                :message="item.message"
                :is-last-message="index === messages.length - 1"
                :sender-name="$t('AUTONOMIA_GUIDE.TITLE')"
              />
              <Button
                v-if="navLocation(item.navigation)"
                :label="
                  item.navigation.label || $t('AUTONOMIA_GUIDE.GO_TO_SCREEN')
                "
                icon="i-lucide-arrow-right"
                trailing-icon
                sm
                slate
                faded
                class="self-start"
                @click="navigateTo(item.navigation)"
              />
            </div>
          </template>
          <CopilotLoader
            v-if="isSending"
            :label="$t('AUTONOMIA_GUIDE.THINKING')"
          />
        </div>
        <div v-else class="flex-1 flex flex-col gap-3 px-1 py-2">
          <h3 class="text-base font-medium text-n-slate-12 leading-7">
            {{ $t('AUTONOMIA_GUIDE.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-6">
            {{ $t('AUTONOMIA_GUIDE.KICK_OFF') }}
          </p>
          <div class="flex flex-col gap-2 mt-2">
            <button
              v-for="(suggestion, i) in suggestions"
              :key="i"
              class="text-left text-sm text-n-slate-12 bg-n-alpha-1 hover:bg-n-alpha-2 rounded-lg px-3 py-2 transition-colors"
              @click="sendMessage(suggestion)"
            >
              {{ suggestion }}
            </button>
          </div>
        </div>
      </div>

      <div class="mx-3 mt-px mb-2">
        <CopilotInput class="mb-1 w-full" @send="sendMessage" />
      </div>
    </div>
  </div>
  <template v-else />
</template>
