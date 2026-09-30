<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useRelationships } from 'dashboard/composables/useRelationships';
import axios from 'dashboard/api/relationships';
import CompanyMedia from 'dashboard/components-next/Relationships/CompanyMedia.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();
const { mediaEnabled, navigationEnabled, accountId } = useRelationships();
const company = ref(null);
const loading = ref(false);
const error = ref(false);
const companyId = computed(() => Number(route.params.companyId));
const companyUrl = computed(
  () => `/api/v1/accounts/${accountId.value}/companies/${companyId.value}`
);
const backToCompany = computed(() => ({
  name: 'companies_dashboard_show',
  params: { accountId: accountId.value, companyId: companyId.value },
  // A truthy media query reopens the media tab, including on a direct visit.
  query: { ...route.query, media: route.query.media || '{}' },
}));
let generation = 0;
const loadCompany = async () => {
  generation += 1;
  const current = generation;
  const context = companyUrl.value;
  company.value = null;
  error.value = false;
  loading.value = false;
  if (!mediaEnabled.value) return;
  loading.value = true;
  try {
    const { data } = await axios.get(context);
    if (current === generation && context === companyUrl.value)
      company.value = data.payload;
  } catch {
    if (current === generation && context === companyUrl.value)
      error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
watch([companyUrl, mediaEnabled], loadCompany, {
  immediate: true,
  flush: 'sync',
});
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <main
    v-if="mediaEnabled"
    class="flex-1 min-w-0 overflow-auto bg-n-surface-1 p-4 md:p-6"
  >
    <nav
      :aria-label="$t('RELATIONSHIPS.MEDIA.BREADCRUMB')"
      class="flex min-w-0 flex-wrap items-center gap-2 text-sm text-n-slate-11"
    >
      <template v-if="navigationEnabled">
        <RouterLink
          :to="{ name: 'relationships_home', params: { accountId } }"
          class="text-n-blue-11 hover:underline"
          >{{ $t('RELATIONSHIPS.TITLE') }}</RouterLink
        >
        <span
          class="i-lucide-chevron-right size-4 shrink-0"
          aria-hidden="true"
        />
      </template>
      <RouterLink
        :to="{ name: 'companies_dashboard_index', params: { accountId } }"
        class="text-n-blue-11 hover:underline"
      >
        {{ $t('RELATIONSHIPS.COMPANIES') }}
      </RouterLink>
      <span class="i-lucide-chevron-right size-4 shrink-0" aria-hidden="true" />
      <RouterLink
        :to="backToCompany"
        :aria-label="$t('RELATIONSHIPS.MEDIA.BACK_TO_COMPANY')"
        class="min-w-0 max-w-full truncate text-n-blue-11 hover:underline"
        :title="company?.name"
      >
        {{ company?.name || $t('RELATIONSHIPS.MEDIA.BACK_TO_COMPANY') }}
      </RouterLink>
      <span class="i-lucide-chevron-right size-4 shrink-0" aria-hidden="true" />
      <span aria-current="page">{{ $t('RELATIONSHIPS.MEDIA.TAB') }}</span>
    </nav>
    <div
      v-if="loading"
      role="status"
      class="flex items-center gap-2 py-6 text-sm text-n-slate-11"
    >
      <Spinner />{{ $t('RELATIONSHIPS.LOADING') }}
    </div>
    <div
      v-else-if="error"
      role="alert"
      class="my-4 rounded-xl border border-n-weak p-4 text-sm text-n-slate-11"
    >
      <p>{{ $t('RELATIONSHIPS.MEDIA.COMPANY_ERROR') }}</p>
      <Button
        type="button"
        sm
        faded
        :label="$t('RELATIONSHIPS.RETRY')"
        @click="loadCompany"
      />
    </div>
    <h1
      v-else-if="company"
      class="mb-2 mt-6 break-words text-2xl font-semibold text-n-slate-12"
    >
      {{ company.name }}
    </h1>
    <CompanyMedia :key="companyUrl" :company-id="companyId" expanded />
  </main>
  <template v-else />
</template>
