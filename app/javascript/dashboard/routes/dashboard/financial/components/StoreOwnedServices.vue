<script setup>
import { computed, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { canAccessStore } from 'dashboard/helper/storeAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import StoreOwnedService from './StoreOwnedService.vue';
import StoreActivationDialog from './StoreActivationDialog.vue';
import StoreRenewalDialog from './StoreRenewalDialog.vue';
import { useStoreActivation } from '../composables/useStoreActivation';
import { useStoreLabels } from '../composables/useStoreLabels';

const { t } = useI18n();
const labels = useStoreLabels();
const route = useRoute();
const store = useStore();
const user = useMapGetter('getCurrentUser');
const allowed = computed(() => canAccessStore(user.value));
const entries = ref([]);
const activations = ref([]);
const accounts = ref([]);
const pagination = ref({ page: 1, totalPages: 0 });
const error = ref('');
const dialog = useTemplateRef('dialog');
const renewalDialog = useTemplateRef('renewalDialog');
const { run, isPending } = useAbortableRequest();
const load = async (page = 1) => {
  entries.value = [];
  activations.value = [];
  error.value = '';
  if (!allowed.value) return;
  try {
    const response = await run(signal => StoreAPI.subscriptions(page, signal));
    if (!response) return;
    entries.value = response.data.data;
    activations.value = response.data.activations;
    pagination.value = response.data.pagination;
    const eligible = await run(signal => StoreAPI.eligibleAccounts(signal));
    if (eligible) accounts.value = eligible.data.data;
  } catch (failure) {
    error.value =
      failure.response?.status === 401
        ? t('FINANCIAL.STORE.SESSION_EXPIRED')
        : t('FINANCIAL.STORE.LOAD_ERROR');
  }
};
const operationControl = useStoreActivation(async result => {
  await load(pagination.value.page);
  if (result.accountId === Number(route.params.accountId))
    await store.dispatch('accounts/get', {
      silent: true,
      accountId: result.accountId,
    });
});
const { busy, errorCode } = operationControl;
watch([() => route.params.accountId, allowed], () => load(), {
  immediate: true,
});
</script>

<template>
  <section class="space-y-4">
    <template v-if="allowed">
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="m-0 text-base font-medium text-n-slate-12">
          {{ t('FINANCIAL.STORE.OWNED') }}
        </h2>
        <Button
          :label="t('FINANCIAL.REFRESH')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          :disabled="isPending || busy"
          @click="load(pagination.page)"
        />
      </header>
      <Spinner v-if="isPending" />
      <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p v-else-if="!entries.length" class="text-sm text-n-slate-11">
        {{ t('FINANCIAL.STORE.NO_OWNED_SERVICES') }}
      </p>
      <p v-if="errorCode" role="alert" class="text-sm text-n-ruby-11">
        {{ labels.errors[errorCode] }}
      </p>
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <StoreOwnedService
          v-for="entry in entries"
          :key="entry.subscription.id"
          :entry="entry"
          :activations="activations"
          :accounts="accounts"
          :busy="busy"
          @activate="dialog?.open(entry)"
          @renewal="renewalDialog?.open(entry)"
          @deactivate="
            record =>
              operationControl.execute(() => StoreAPI.deactivate(record.id))
          "
          @resume="
            record =>
              operationControl.execute(() =>
                StoreAPI.resumeActivation(record.id)
              )
          "
        />
      </div>
      <nav
        v-if="pagination.totalPages > 1"
        :aria-label="t('FINANCIAL.STORE.PAGINATION')"
        class="flex justify-center gap-3"
      >
        <Button
          icon="i-lucide-chevron-left"
          :aria-label="t('FINANCIAL.STORE.PREVIOUS')"
          :disabled="pagination.page <= 1 || isPending"
          @click="load(pagination.page - 1)"
        />
        <span class="text-sm text-n-slate-11">{{
          t('FINANCIAL.STORE.PAGE', {
            page: pagination.page,
            total: pagination.totalPages,
          })
        }}</span>
        <Button
          icon="i-lucide-chevron-right"
          :aria-label="t('FINANCIAL.STORE.NEXT')"
          :disabled="pagination.page >= pagination.totalPages || isPending"
          @click="load(pagination.page + 1)"
        />
      </nav>
      <StoreActivationDialog ref="dialog" @changed="load(pagination.page)" />
      <StoreRenewalDialog
        ref="renewalDialog"
        @changed="load(pagination.page)"
      />
    </template>
  </section>
</template>
