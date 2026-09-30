<script setup>
import { onMounted, computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useRelationships } from 'dashboard/composables/useRelationships';
import ContactDetailActions from 'dashboard/components-next/Relationships/ContactDetailActions.vue';
import RelationshipTabs from 'dashboard/components-next/Relationships/RelationshipTabs.vue';
import RelationshipBreadcrumb from 'dashboard/components-next/Relationships/RelationshipBreadcrumb.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';

import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactDetails from 'dashboard/components-next/Contacts/Pages/ContactDetails.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ContactNotes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue';
import ContactHistory from 'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue';
import ContactMedia from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMedia.vue';
import ContactMerge from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue';
import ContactCustomAttributes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue';

const { navigationEnabled, mediaEnabled, accountId } = useRelationships();
const store = useStore();
const route = useRoute();
const router = useRouter();

const contact = useMapGetter('contacts/getContactById');
const uiFlags = useMapGetter('contacts/getUIFlags');

const activeTab = ref(
  mediaEnabled.value && route.query.media ? 'media' : 'notes'
);
const contactMergeRef = ref(null);

const isFetchingItem = computed(() => uiFlags.value.isFetchingItem);
const isMergingContact = computed(() => uiFlags.value.isMerging);
const isUpdatingContact = computed(() => uiFlags.value.isUpdating);

const selectedContact = computed(() => contact.value(route.params.contactId));

const showSpinner = computed(
  () => isFetchingItem.value || isMergingContact.value
);

const { t } = useI18n();

const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  { key: 'NOTES', value: 'notes' },
  { key: 'MEDIA', value: 'media' },
  { key: 'MERGE', value: 'merge' },
];

const tabs = computed(() => {
  return CONTACT_TABS_OPTIONS.map(tab => ({
    label: t(`CONTACTS_LAYOUT.SIDEBAR.TABS.${tab.key}`),
    value: tab.value,
  }));
});

const activeTabIndex = computed(() => {
  return CONTACT_TABS_OPTIONS.findIndex(v => v.value === activeTab.value);
});

const goToContactsList = () => {
  if (window.history.state?.back || window.history.length > 1) {
    router.back();
  } else {
    router.push(`/app/accounts/${route.params.accountId}/contacts?page=1`);
  }
};

const fetchActiveContact = async () => {
  const { accountId: requestedAccountId, contactId } = route.params;
  if (!contactId) return;
  await store.dispatch('contacts/show', { id: contactId });
  if (
    route.params.accountId === requestedAccountId &&
    route.params.contactId === contactId
  ) {
    await store.dispatch('contacts/fetchContactableInbox', contactId);
  }
};

const handleTabChange = tab => {
  activeTab.value = tab.value;
};

const fetchContactNotes = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactNotes/get', { contactId });
};

const fetchContactConversations = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactConversations/get', contactId);
};

const fetchAttributes = () => {
  store.dispatch('attributes/get');
};

const toggleContactBlock = async isBlocked => {
  const ALERT_MESSAGES = {
    success: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_SUCCESS_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_SUCCESS_MESSAGE'),
    },
    error: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_ERROR_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE'),
    },
  };

  try {
    await store.dispatch(`contacts/update`, {
      id: selectedContact.value.id,
      blocked: !isBlocked,
    });
    useAlert(
      isBlocked ? ALERT_MESSAGES.success.unblock : ALERT_MESSAGES.success.block
    );
  } catch (error) {
    useAlert(
      isBlocked ? ALERT_MESSAGES.error.unblock : ALERT_MESSAGES.error.block
    );
  }
};

watch([() => route.params.accountId, () => route.params.contactId], () => {
  activeTab.value = mediaEnabled.value && route.query.media ? 'media' : 'notes';
  fetchActiveContact();
  fetchContactNotes();
  fetchContactConversations();
});

watch(mediaEnabled, enabled => {
  if (enabled && route.query.media) activeTab.value = 'media';
});

onMounted(() => {
  fetchActiveContact();
  fetchContactNotes();
  fetchContactConversations();
  fetchAttributes();
});
</script>

<template>
  <div
    class="flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1"
  >
    <ContactsDetailsLayout
      :relationships-layout="navigationEnabled"
      :button-label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
      :selected-contact="selectedContact"
      is-detail-view
      :show-pagination-footer="false"
      :is-updating="isUpdatingContact"
      @go-to-contacts-list="goToContactsList"
      @toggle-block="toggleContactBlock"
    >
      <template v-if="navigationEnabled" #breadcrumb>
        <RelationshipBreadcrumb
          :items="[
            {
              key: 'CONTACTS',
              to: { name: 'contacts_dashboard_index', params: { accountId } },
            },
            ...(selectedContact?.name ? [{ label: selectedContact.name }] : []),
          ]"
        />
      </template>
      <div
        v-if="showSpinner"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>
      <ContactDetails
        v-else-if="selectedContact"
        :key="selectedContact.id"
        :selected-contact="selectedContact"
        @go-to-contacts-list="goToContactsList"
      >
        <template v-if="navigationEnabled" #actions>
          <ContactDetailActions
            :contact="selectedContact"
            :is-updating="isUpdatingContact"
            @toggle-block="toggleContactBlock"
          />
        </template>
      </ContactDetails>
      <template #sidebarHeader="{ context = 'desktop' }">
        <RelationshipTabs
          v-if="navigationEnabled"
          :id="`contact-sidebar-${context}`"
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          @tab-changed="handleTabChange"
        />
        <div v-else class="min-w-0 overflow-x-auto px-4 pt-6 pb-3">
          <TabBar
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            class="w-max min-w-full [&>button]:w-auto [&>button]:shrink-0 bg-n-alpha-black2"
            @tab-changed="handleTabChange"
          />
        </div>
      </template>
      <template #sidebar="{ context = 'desktop' }">
        <div
          :id="
            navigationEnabled ? `contact-sidebar-${context}-panel` : undefined
          "
          :role="navigationEnabled ? 'tabpanel' : undefined"
          :aria-labelledby="
            navigationEnabled
              ? `contact-sidebar-${context}-${activeTab}`
              : undefined
          "
        >
          <div
            v-if="isFetchingItem"
            class="flex items-center justify-center py-10 text-n-slate-11"
          >
            <Spinner />
          </div>
          <template v-else>
            <ContactCustomAttributes
              v-if="activeTab === 'attributes'"
              :selected-contact="selectedContact"
            />
            <ContactNotes
              v-if="activeTab === 'notes'"
              :key="`${accountId}:${route.params.contactId}`"
            />
            <ContactHistory v-if="activeTab === 'history'" />
            <ContactMedia v-if="activeTab === 'media'" />
            <ContactMerge
              v-if="activeTab === 'merge'"
              ref="contactMergeRef"
              :selected-contact="selectedContact"
              @go-to-contacts-list="goToContactsList"
              @reset-tab="handleTabChange(CONTACT_TABS_OPTIONS[0])"
            />
          </template>
        </div>
      </template>
    </ContactsDetailsLayout>
  </div>
</template>
