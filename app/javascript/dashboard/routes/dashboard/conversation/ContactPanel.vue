<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useLayoutExpandidoDaLista } from 'dashboard/components-next/Conversation/ListaDeConversas/useLayoutDaLista';
import { useCanOperateConversation } from 'dashboard/composables/useCanOperateConversation';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import AcoesSoLeitura from './AcoesSoLeitura.vue';
import ParticipantesSoLeitura from './ParticipantesSoLeitura.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContatoBasico from './contact/ContatoBasico.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import ContactOriginsPanel from 'dashboard/components-next/CampaignJourney/ContactOriginsPanel.vue';
// #2138: o painel novo do contato, com a chave painel_contato_enxuto da conta.
import PainelDoContato from 'dashboard/components-next/painel-do-contato/PainelDoContato.vue';
import { usePainelNovo } from 'dashboard/components-next/painel-do-contato/usePainelNovo';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();
// #2202: com a lista nova, o layout é sempre o condensado.
const isOnExpandedLayout = useLayoutExpandidoDaLista();

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();
const painelNovo = usePainelNovo();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
// Quem só lê (#1800) não atribui, não mexe em participantes nem roda macro.
const canOperate = useCanOperateConversation(currentChat);
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

// Sem ver contatos (#1849), o painel mostra o contato que veio com a conversa: nome, telefone e e-mail.
const { canViewRelationshipRecords: podeVerContatos } =
  useRelationshipPermissions();
const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() =>
  podeVerContatos.value
    ? contactGetter.value(contactId.value)
    : currentChat.value.meta?.sender || {}
);
const contactAdditionalAttributes = computed(() =>
  podeVerContatos.value ? contact.value.additional_attributes || {} : {}
);

const appliedContactFilter = useMapGetter('getAppliedContactFilter');

const isListScopedToContact = computed(
  () =>
    !isOnExpandedLayout.value &&
    appliedContactFilter.value?.id === contactId.value
);

const getContactDetails = () => {
  if (contactId.value && podeVerContatos.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});
</script>

<template>
  <!-- #2138: com a chave painel_contato_enxuto, o painel novo; sem ela, o de sempre. -->
  <PainelDoContato
    v-if="painelNovo"
    class="w-full"
    :conversation="currentChat"
    :contact="contact"
    :pode-ver-contatos="podeVerContatos"
    :pode-operar="canOperate"
    :conversation-attributes="conversationAdditionalAttributes"
    @fechar="closeContactPanel"
  />
  <div v-else class="w-full">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    />
    <ContactInfo
      v-if="podeVerContatos"
      :contact="contact"
      :channel-type="channelType"
    />
    <ContatoBasico
      v-else
      :contact="contact"
      :conversation-id="conversationId"
    />
    <ContactOriginsPanel
      :contact-id="contactId"
      :conversation-attributes="conversationAdditionalAttributes"
    />
    <div class="px-2 pb-8 list-group">
      <Draggable
        :list="conversationSidebarItems"
        animation="200"
        ghost-class="ghost"
        handle=".drag-handle"
        item-key="name"
        class="flex flex-col gap-3"
        @start="dragging = true"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <div
            v-if="element.name === 'conversation_actions'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="
                canOperate
                  ? $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')
                  : $t('CONVERSATION.SO_LEITURA.RESUMO')
              "
              :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
              @toggle="
                value => toggleSidebarUIState('is_conv_actions_open', value)
              "
            >
              <ConversationAction
                v-if="canOperate"
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
              <AcoesSoLeitura v-else />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'conversation_participants'"
            class="conversation--actions"
          >
            <AccordionItem
              :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
              :is-open="isContactSidebarItemOpen('is_conv_participants_open')"
              @toggle="
                value =>
                  toggleSidebarUIState('is_conv_participants_open', value)
              "
            >
              <ConversationParticipant
                v-if="canOperate"
                :conversation-id="conversationId"
                :inbox-id="inboxId"
              />
              <ParticipantesSoLeitura
                v-else
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'conversation_info'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
              :is-open="isContactSidebarItemOpen('is_conv_details_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_conv_details_open', value)
              "
            >
              <ConversationInfo
                :conversation-attributes="conversationAdditionalAttributes"
                :contact-attributes="contactAdditionalAttributes"
              />
            </AccordionItem>
          </div>
          <div
            v-else-if="element.name === 'contact_attributes' && podeVerContatos"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
              :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
              compact
              @toggle="
                value =>
                  toggleSidebarUIState('is_contact_attributes_open', value)
              "
            >
              <CustomAttributes
                attribute-type="contact_attribute"
                attribute-from="conversation_contact_panel"
                :contact-id="contact.id"
                :empty-state-message="
                  $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                "
              />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'previous_conversation' && !isListScopedToContact
            "
          >
            <AccordionItem
              v-if="contact.id"
              :title="
                $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
              "
              :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_previous_conv_open', value)
              "
            >
              <ContactConversations
                :contact-id="contact.id"
                :conversation-id="conversationId"
              />
            </AccordionItem>
          </div>
          <woot-feature-toggle
            v-else-if="element.name === 'macros' && canOperate"
            feature-key="macros"
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
              :is-open="isContactSidebarItemOpen('is_macro_open')"
              compact
              @toggle="value => toggleSidebarUIState('is_macro_open', value)"
            >
              <MacrosList :conversation-id="conversationId" />
            </AccordionItem>
          </woot-feature-toggle>
          <div
            v-else-if="
              element.name === 'linear_issues' &&
              isLinearFeatureEnabled &&
              isLinearClientIdConfigured
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
              :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_linear_issues_open', value)
              "
            >
              <LinearSetupCTA v-if="!isLinearConnected" />
              <LinearIssuesList v-else :conversation-id="conversationId" />
            </AccordionItem>
          </div>
          <div
            v-else-if="
              element.name === 'shopify_orders' &&
              isShopifyFeatureEnabled &&
              podeVerContatos
            "
          >
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
              :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shopify_orders_open', value)
              "
            >
              <ShopifyOrdersList :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'contact_notes' && podeVerContatos">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
              :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_contact_notes_open', value)
              "
            >
              <ContactNotes :contact-id="contactId" />
            </AccordionItem>
          </div>
          <div v-else-if="element.name === 'shared_files'">
            <AccordionItem
              :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
              :is-open="isContactSidebarItemOpen('is_shared_files_open')"
              compact
              @toggle="
                value => toggleSidebarUIState('is_shared_files_open', value)
              "
            >
              <SharedFiles />
            </AccordionItem>
          </div>
        </template>
      </Draggable>
    </div>
  </div>
</template>

<style lang="scss" scoped>
:deep(.contact--profile) {
  @apply pb-3 border-b border-solid border-n-weak;
}
</style>
