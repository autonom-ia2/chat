<script setup>
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { canAccessStore } from 'dashboard/helper/storeAccess';
import StoreAPI from 'dashboard/api/autonomia/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StoreServiceCard from '../components/StoreServiceCard.vue';
import StoreServiceDialog from '../components/StoreServiceDialog.vue';
import StoreFeaturesDialog from '../components/StoreFeaturesDialog.vue';
import StoreOwnedServices from '../components/StoreOwnedServices.vue';
import StoreCheckoutReturn from '../components/StoreCheckoutReturn.vue';
import { checkoutStorageKey } from '../helpers/storeCheckout';
import { useStoreLabels } from '../composables/useStoreLabels';

const { t } = useI18n();
const labels = useStoreLabels();
const route = useRoute();
const router = useRouter();
const user = useMapGetter('getCurrentUser');
const allowed = computed(() => canAccessStore(user.value));
const buyerScope = computed(() =>
  checkoutStorageKey(user.value?.id, route.params.accountId)
);
const view = computed(() =>
  route.query?.view === 'services' ? 'services' : 'catalog'
);
const showOwned = () =>
  router.replace({ query: { ...route.query, view: 'services' } });
const showCatalog = () =>
  router.replace({ query: { ...route.query, view: 'catalog' } });
const dialog = useTemplateRef('dialog');
const featuresDialog = useTemplateRef('featuresDialog');
const items = ref([]);
const pagination = ref({ page: 1, totalPages: 0, totalItems: 0 });
const loading = ref(false);
const error = ref('');
const groups = computed(() =>
  ['feature', 'agent']
    .map(key => ({
      key,
      items: items.value.filter(item => item.group === key),
    }))
    .filter(group => group.items.length)
);
let request;

const load = async (page = 1) => {
  request?.abort();
  items.value = [];
  error.value = '';
  if (!allowed.value) return;
  const controller = new AbortController();
  request = controller;
  loading.value = true;
  try {
    const response = await StoreAPI.catalog(page, controller.signal);
    if (request !== controller || controller.signal.aborted) return;
    items.value = response.data.data;
    pagination.value = response.data.pagination;
  } catch (failure) {
    if (controller.signal.aborted) return;
    error.value =
      failure.response?.status === 401
        ? t('FINANCIAL.STORE.SESSION_EXPIRED')
        : t('FINANCIAL.STORE.LOAD_ERROR');
  } finally {
    if (request === controller) loading.value = false;
  }
};
watch(
  [() => route.params.accountId, allowed, view],
  () => {
    if (view.value === 'catalog') load();
    else request?.abort();
  },
  {
    immediate: true,
  }
);
onBeforeUnmount(() => request?.abort());
</script>

<template>
  <main class="h-full min-w-0 overflow-auto bg-n-surface-1">
    <section
      v-if="allowed"
      class="max-w-6xl px-4 py-6 mx-auto space-y-6 md:px-6"
    >
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="m-0 text-2xl font-semibold text-n-slate-12">
          {{ t('FINANCIAL.STORE.TITLE') }}
        </h1>
        <Button
          v-if="view === 'catalog'"
          :label="t('FINANCIAL.REFRESH')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          color="slate"
          :disabled="loading"
          @click="load(pagination.page)"
        />
        <Button
          v-if="view === 'catalog'"
          :label="t('FINANCIAL.STORE.MANAGE_FEATURES')"
          icon="i-lucide-blocks"
          variant="ghost"
          color="slate"
          @click="featuresDialog?.open()"
        />
      </header>
      <nav
        :aria-label="t('FINANCIAL.STORE.NAVIGATION')"
        class="flex flex-wrap gap-2"
      >
        <Button
          :label="t('FINANCIAL.STORE.CATALOG')"
          icon="i-lucide-layout-grid"
          :variant="view === 'catalog' ? 'faded' : 'ghost'"
          :aria-pressed="view === 'catalog'"
          @click="showCatalog"
        />
        <Button
          :label="t('FINANCIAL.STORE.OWNED')"
          icon="i-lucide-package"
          :variant="view === 'services' ? 'faded' : 'ghost'"
          :aria-pressed="view === 'services'"
          @click="showOwned"
        />
      </nav>
      <StoreCheckoutReturn
        v-if="typeof route.query?.checkout_operation === 'string'"
        :key="route.params.accountId"
        :operation-id="route.query.checkout_operation"
        :buyer-scope="buyerScope"
        :cancelled="route.query.checkout_result === 'cancel'"
        @confirmed="showOwned"
      />
      <StoreOwnedServices
        v-if="view === 'services'"
        :key="route.params.accountId"
      />
      <div
        v-else-if="loading"
        role="status"
        class="flex items-center justify-center gap-2 py-16 text-n-slate-11"
      >
        <Spinner />{{ t('FINANCIAL.STORE.LOADING') }}
      </div>
      <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p v-else-if="!items.length" class="py-12 text-sm text-n-slate-11">
        {{ t('FINANCIAL.STORE.EMPTY') }}
      </p>
      <template v-else>
        <section v-for="group in groups" :key="group.key" class="space-y-3">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ labels.groups[group.key] }}
          </h2>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <StoreServiceCard
              v-for="item in group.items"
              :key="item.service.id"
              :item="item"
              @details="item => dialog?.open(item)"
            />
          </div>
        </section>
        <nav
          v-if="pagination.totalPages > 1"
          :aria-label="t('FINANCIAL.STORE.PAGINATION')"
          class="flex flex-wrap items-center justify-center gap-3"
        >
          <Button
            icon="i-lucide-chevron-left"
            :aria-label="t('FINANCIAL.STORE.PREVIOUS')"
            variant="ghost"
            color="slate"
            :disabled="pagination.page <= 1"
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
            variant="ghost"
            color="slate"
            :disabled="pagination.page >= pagination.totalPages"
            @click="load(pagination.page + 1)"
          />
        </nav>
      </template>
      <StoreServiceDialog
        :key="route.params.accountId"
        ref="dialog"
        :checkout-enabled="allowed"
        :buyer-scope="buyerScope"
        @owned="showOwned"
      />
      <StoreFeaturesDialog :key="route.params.accountId" ref="featuresDialog" />
    </section>
    <p v-else class="p-6 text-sm text-n-slate-11">
      {{ t('FINANCIAL.STORE.FORBIDDEN') }}
    </p>
  </main>
</template>
