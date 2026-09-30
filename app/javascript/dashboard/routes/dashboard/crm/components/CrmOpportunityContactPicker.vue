<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ContactAPI from 'dashboard/api/contacts';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.OPPORTUNITY.${key}`);
const { accountId, currentAccount, isCloudFeatureEnabled } = useAccount();
const companiesEnabled = computed(() =>
  Boolean(currentAccount.value?.id && isCloudFeatureEnabled('companies'))
);
const request = useAbortableRequest();
const query = ref('');
const results = ref([]);
const page = ref(1);
const hasMore = ref(false);
const searched = ref(false);
const failed = ref(false);
const search = async (nextPage = 1) => {
  if (props.disabled || query.value.trim().length < 2) return;
  failed.value = false;
  results.value = [];
  try {
    const response = await request.run(signal =>
      ContactAPI.search(query.value.trim(), nextPage, 'name', '', {
        signal,
        includeCompany: companiesEnabled.value,
      })
    );
    if (!response) return;
    results.value = response.data.payload;
    hasMore.value = response.data.meta.has_more === true;
    page.value = nextPage;
    searched.value = true;
  } catch {
    failed.value = true;
  }
};
const select = contact => {
  if (props.disabled) return;
  request.abort();
  emit('update:modelValue', contact);
};
const resetSearch = () => {
  request.abort();
  results.value = [];
  hasMore.value = false;
  searched.value = false;
  failed.value = false;
  page.value = 1;
};
watch(query, resetSearch, { flush: 'sync' });
watch(
  [accountId, companiesEnabled],
  () => {
    query.value = '';
    resetSearch();
    emit('update:modelValue', null);
  },
  { flush: 'sync' }
);
</script>

<template>
  <section
    v-if="modelValue"
    class="grid gap-4 rounded-xl border border-n-brand/30 bg-n-brand/5 p-4"
    data-opportunity-selected-contact
  >
    <header class="flex items-center justify-between gap-3">
      <span class="flex items-center gap-2 text-xs font-medium text-n-blue-11">
        <span class="i-lucide-link-2 size-4" aria-hidden="true" />
        {{ label('EXISTING_RECORD') }}
      </span>
      <Button
        type="button"
        sm
        ghost
        :label="label('CHANGE_CONTACT')"
        :disabled="disabled"
        @click="select(null)"
      />
    </header>
    <div class="flex items-center gap-3">
      <Avatar
        :name="modelValue.name || ''"
        :src="modelValue.thumbnail || ''"
        :size="44"
        rounded-full
      />
      <div class="min-w-0 flex-1">
        <h3 class="m-0 break-words text-base font-semibold text-n-slate-12">
          {{ modelValue.name }}
        </h3>
        <p
          v-if="companiesEnabled"
          class="mb-0 mt-1 break-words text-sm text-n-slate-11"
        >
          {{
            modelValue.company?.name ||
            label(modelValue.company_id ? 'COMPANY_UNAVAILABLE' : 'NO_COMPANY')
          }}
        </p>
      </div>
    </div>
    <dl class="m-0 grid min-w-0 grid-cols-1 gap-3 min-[440px]:grid-cols-2">
      <div class="min-w-0">
        <dt class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span class="i-lucide-mail size-3.5" aria-hidden="true" />{{
            label('EMAIL')
          }}
        </dt>
        <dd class="m-0 break-words text-sm text-n-slate-12">
          {{ modelValue.email || label('NOT_INFORMED') }}
        </dd>
      </div>
      <div class="min-w-0">
        <dt class="mb-1 flex items-center gap-2 text-xs text-n-slate-11">
          <span class="i-lucide-phone size-3.5" aria-hidden="true" />{{
            label('PHONE')
          }}
        </dt>
        <dd class="m-0 break-words text-sm text-n-slate-12">
          {{ modelValue.phone_number || label('NOT_INFORMED') }}
        </dd>
      </div>
    </dl>
  </section>
  <div v-else class="grid gap-3" data-opportunity-contact-search>
    <div class="flex min-w-0 items-end gap-3">
      <Input
        v-model="query"
        class="min-w-0 flex-1"
        :label="label('SEARCH_CONTACT')"
        :placeholder="
          label(companiesEnabled ? 'SEARCH_WITH_COMPANY' : 'SEARCH_PLACEHOLDER')
        "
        :disabled="disabled"
        autocomplete="off"
        @enter="search()"
        @keydown.enter.stop.prevent
      />
      <Button
        type="button"
        icon="i-lucide-search"
        slate
        faded
        :label="label('SEARCH')"
        :disabled="disabled || query.trim().length < 2"
        :is-loading="request.isPending.value"
        @click="search()"
      />
    </div>
    <p
      v-if="request.isPending.value"
      role="status"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ label('SEARCHING') }}
    </p>
    <div
      v-else-if="failed"
      role="alert"
      class="grid gap-2 rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      <p class="m-0">{{ label('SEARCH_ERROR') }}</p>
      <Button
        type="button"
        sm
        ghost
        :label="label('RETRY')"
        :disabled="disabled"
        class="justify-self-start"
        @click="search()"
      />
    </div>
    <template v-else-if="results.length">
      <div class="overflow-hidden rounded-xl border border-n-weak">
        <button
          v-for="contact in results"
          :key="contact.id"
          type="button"
          class="flex min-h-16 w-full items-center gap-3 border-b border-n-weak p-3 text-start last:border-0 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-n-brand"
          :disabled="disabled"
          data-opportunity-contact-result
          @click="select(contact)"
        >
          <Avatar
            :name="contact.name || ''"
            :src="contact.thumbnail || ''"
            :size="36"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <div class="truncate text-sm font-medium text-n-slate-12">
              {{ contact.name }}
            </div>
            <div class="truncate text-xs text-n-slate-11">
              {{ contact.email || contact.phone_number || label('NO_CHANNEL') }}
            </div>
            <div
              v-if="companiesEnabled && contact.company"
              class="mt-0.5 truncate text-xs text-n-slate-11"
            >
              {{ contact.company.name }}
            </div>
          </div>
          <span
            class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
        </button>
      </div>
      <div
        v-if="hasMore || page > 1"
        class="flex items-center justify-between gap-2 text-xs text-n-slate-11"
      >
        <Button
          type="button"
          sm
          ghost
          slate
          :label="label('PREVIOUS')"
          :disabled="disabled || page <= 1"
          @click="search(page - 1)"
        />
        <span>{{ t('CRM_KANBAN.OPPORTUNITY.PAGE', { page }) }}</span>
        <Button
          type="button"
          sm
          ghost
          slate
          :label="label('NEXT')"
          :disabled="disabled || !hasMore"
          @click="search(page + 1)"
        />
      </div>
    </template>
    <div
      v-else-if="searched"
      role="status"
      class="rounded-xl border border-dashed border-n-strong p-4 text-sm text-n-slate-11"
    >
      {{ label('NO_RESULTS') }}
    </div>
    <p v-else class="m-0 text-xs leading-5 text-n-slate-11">
      {{ label('SEARCH_HINT') }}
    </p>
  </div>
</template>
