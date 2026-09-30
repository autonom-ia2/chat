<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  ready: { type: Boolean, default: false },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['open', 'cancel']);
const route = useRoute();
const { t } = useI18n();
const { currentAccount, isCloudFeatureEnabled } = useAccount();
const request = useAbortableRequest();
const contact = ref(null);
const failed = ref(false);
const emitted = ref(false);
const contactId = computed(() => {
  const value = route.query.new_contact_id;
  if (typeof value !== 'string' || !value) return null;
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 && String(number) === value
    ? number
    : null;
});
const companiesEnabled = computed(() =>
  Boolean(currentAccount.value?.id && isCloudFeatureEnabled('companies'))
);
const allowed = computed(
  () => props.canManage && window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
);
const invalid = computed(
  () => !contactId.value || route.query.card_id !== undefined
);
const canOpen = computed(() =>
  Boolean(
    contact.value && props.ready && allowed.value && !request.isPending.value
  )
);
const message = computed(() => {
  if (!allowed.value) return 'UNAVAILABLE';
  if (invalid.value) return 'INVALID_LINK';
  if (request.isPending.value) return 'LOADING';
  if (failed.value) return 'LOAD_ERROR';
  return props.ready ? 'READY' : 'NEEDS_PIPELINE';
});
const open = () => {
  if (!canOpen.value) return;
  emitted.value = true;
  emit('open', contact.value);
};
const load = async () => {
  request.abort();
  contact.value = null;
  failed.value = false;
  emitted.value = false;
  if (!allowed.value || invalid.value) return;
  try {
    const person = await request.run(async signal => {
      const result = (await ContactAPI.show(contactId.value)).data.payload;
      if (signal.aborted) return undefined;
      if (companiesEnabled.value && result.company_id) {
        result.company = (
          await CompanyAPI.show(result.company_id)
        ).data.payload;
      }
      return result;
    });
    if (person) contact.value = person;
  } catch {
    failed.value = true;
  }
};
watch(
  [
    () => route.params.accountId,
    () => route.query.new_contact_id,
    () => route.query.card_id,
    allowed,
    companiesEnabled,
  ],
  load,
  { immediate: true, flush: 'sync' }
);
watch(
  canOpen,
  value => {
    if (value && !emitted.value) open();
  },
  { flush: 'post' }
);
</script>

<template>
  <section
    class="mx-8 mt-4 flex flex-wrap items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    data-opportunity-from-contact
    :role="failed || invalid || !allowed ? 'alert' : 'status'"
  >
    <span
      class="i-lucide-contact-round size-5 shrink-0 text-n-blue-11"
      aria-hidden="true"
    />
    <p class="m-0 min-w-0 flex-1 text-sm leading-6 text-n-slate-12">
      {{ t(`CRM_KANBAN.OPPORTUNITY.CONTEXT.${message}`) }}
    </p>
    <Button
      v-if="failed && allowed && !invalid"
      sm
      faded
      type="button"
      :label="t('CRM_KANBAN.OPPORTUNITY.RETRY')"
      @click="load"
    />
    <Button
      v-if="canOpen"
      sm
      faded
      type="button"
      :label="t('CRM_KANBAN.OPPORTUNITY.CONTEXT.OPEN')"
      @click="open"
    />
    <Button
      sm
      ghost
      slate
      type="button"
      :label="t('CRM_KANBAN.DRAWER.CANCEL')"
      @click="emit('cancel')"
    />
  </section>
</template>
