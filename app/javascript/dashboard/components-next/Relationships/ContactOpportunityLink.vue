<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const { accountId } = useAccount();
const { canViewCrm, canManageCards } = useCrmPermissions();
const visible = computed(
  () =>
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
    canViewCrm.value &&
    canManageCards.value &&
    Boolean(props.contactId)
);
const destination = computed(() => ({
  name: 'crm_kanban_index',
  params: { accountId: accountId.value },
  query: { new_contact_id: String(props.contactId) },
}));
</script>

<template>
  <RouterLink
    v-if="visible"
    :to="destination"
    target="_blank"
    rel="noopener noreferrer"
    :title="t('CRM_KANBAN.OPPORTUNITY.CONTEXT.OPEN_NEW_TAB')"
    :aria-label="t('CRM_KANBAN.OPPORTUNITY.CONTEXT.OPEN_NEW_TAB')"
    class="col-span-2 inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-n-brand/30 bg-n-brand/10 px-3 py-2 text-sm font-medium text-n-blue-11 hover:bg-n-brand/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand xl:w-auto"
    data-contact-new-opportunity
  >
    <span class="i-lucide-plus size-4" aria-hidden="true" />
    {{ t('CRM_KANBAN.OPPORTUNITY.CONTEXT.LABEL') }}
    <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
  </RouterLink>
  <template v-else />
</template>
