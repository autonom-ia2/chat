<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CompanyAPI from 'dashboard/api/companies';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({ disabled: { type: Boolean, default: false } });
const selected = defineModel({ type: Object, default: null });
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.OPPORTUNITY.REGISTRATION.${key}`);
const request = useAbortableRequest();
const query = ref('');
const results = ref([]);
const page = ref(1);
const total = ref(0);
const searched = ref(false);
const failed = ref(false);
watch(
  query,
  () => {
    request.abort();
    results.value = [];
    page.value = 1;
    total.value = 0;
    searched.value = false;
    failed.value = false;
  },
  { flush: 'sync' }
);
const search = async (nextPage = 1) => {
  if (props.disabled || query.value.trim().length < 2) return;
  failed.value = false;
  results.value = [];
  try {
    const response = await request.run(() =>
      CompanyAPI.search(query.value.trim(), nextPage, 'name')
    );
    if (!response) return;
    results.value = response.data.payload;
    total.value = response.data.meta.total_count;
    page.value = nextPage;
    searched.value = true;
  } catch {
    failed.value = true;
  }
};
</script>

<template>
  <div
    v-if="selected"
    class="grid gap-3 rounded-lg border border-n-brand/30 bg-n-brand/5 p-4"
    data-registration-company-selected
  >
    <div class="flex items-center justify-between gap-3">
      <span class="text-xs font-medium text-n-blue-11">{{
        label('COMPANY_SELECTED')
      }}</span>
      <Button
        type="button"
        sm
        ghost
        :label="label('CHANGE')"
        :disabled="disabled"
        @click="selected = null"
      />
    </div>
    <div class="min-w-0">
      <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
        {{ selected.name }}
      </p>
      <p class="mb-0 mt-1 break-all text-xs text-n-slate-11">
        {{ selected.domain || label('NO_DOMAIN') }}
      </p>
    </div>
  </div>
  <div v-else class="grid gap-3" data-registration-company-search>
    <div class="flex min-w-0 items-end gap-3">
      <Input
        v-model="query"
        class="min-w-0 flex-1"
        :label="label('SEARCH_COMPANY')"
        :placeholder="label('SEARCH_COMPANY_HINT')"
        :disabled="disabled"
        @enter="search()"
        @keydown.enter.stop.prevent
      />
      <Button
        type="button"
        slate
        faded
        icon="i-lucide-search"
        :label="label('SEARCH')"
        :is-loading="request.isPending.value"
        :disabled="disabled || query.trim().length < 2"
        @click="search()"
      />
    </div>
    <p v-if="failed" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ label('LOOKUP_ERROR') }}
    </p>
    <p
      v-else-if="request.isPending.value"
      role="status"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ label('LOOKING_UP') }}
    </p>
    <div
      v-else-if="results.length"
      class="max-h-64 overflow-y-auto rounded-lg border border-n-weak"
    >
      <button
        v-for="item in results"
        :key="item.id"
        type="button"
        class="flex min-h-16 w-full items-center gap-3 border-b border-n-weak p-3 text-start last:border-0 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-n-brand"
        :disabled="disabled"
        data-registration-company-result
        @click="selected = item"
      >
        <span
          class="i-lucide-building-2 size-5 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1">
          <span class="block break-words text-sm font-medium text-n-slate-12">{{
            item.name
          }}</span>
          <span class="mt-1 block break-all text-xs text-n-slate-11">{{
            item.domain ||
            item.additional_attributes?.city ||
            label('NO_DOMAIN')
          }}</span>
        </span>
        <span
          class="i-lucide-chevron-right size-4 text-n-slate-11"
          aria-hidden="true"
        />
      </button>
    </div>
    <p v-else class="m-0 text-xs leading-5 text-n-slate-11">
      {{ label(searched ? 'NO_COMPANIES' : 'SEARCH_COMPANY_HINT') }}
    </p>
    <div v-if="total > 25" class="flex items-center justify-between gap-2">
      <Button
        type="button"
        sm
        ghost
        :label="t('CRM_KANBAN.OPPORTUNITY.PREVIOUS')"
        :disabled="disabled || request.isPending.value || page <= 1"
        @click="search(page - 1)"
      />
      <span class="text-xs text-n-slate-11">{{
        t('CRM_KANBAN.OPPORTUNITY.PAGE', { page })
      }}</span>
      <Button
        type="button"
        sm
        ghost
        :label="t('CRM_KANBAN.OPPORTUNITY.NEXT')"
        :disabled="disabled || request.isPending.value || page * 25 >= total"
        @click="search(page + 1)"
      />
    </div>
  </div>
</template>
