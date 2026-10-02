<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useCompaniesStore } from 'dashboard/stores/companies';
import CompanyAPI from 'dashboard/api/companies';
import ContactAPI from 'dashboard/api/contacts';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  contact: { type: Object, required: true },
  company: { type: Object, default: null },
  mode: { type: String, required: true },
  formId: { type: String, required: true },
  readOnly: { type: Boolean, default: false },
});
const emit = defineEmits(['saved']);
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.${key}`);
const { accountId } = useAccount();
const companies = useCompaniesStore();
const request = useAbortableRequest();
const formElement = ref(null);
const initial = {
  name: props.company?.name || '',
  domain: props.company?.domain || '',
  description: props.company?.description || '',
  city: props.company?.additionalAttributes?.city || '',
};
const form = ref({ ...initial });
const query = ref('');
const submittedQuery = ref('');
const results = ref([]);
const selected = ref(null);
const page = ref(1);
const total = ref(0);
const searched = ref(false);
const searchError = ref(false);
const error = ref('');
const saving = ref(false);
let disposed = false;
const context = computed(
  () =>
    `${accountId.value}:${props.contact.id}:${props.contact.company_id || ''}:${props.company?.id || ''}:${props.mode}`
);
const openedContext = context.value;
const stale = computed(() => context.value !== openedContext);
const dirty = computed(() =>
  props.mode === 'edit'
    ? Object.keys(initial).some(
        key => form.value[key].trim() !== initial[key].trim()
      )
    : props.mode === 'link' && Boolean(selected.value)
);
const canSave = computed(() => {
  if (props.readOnly || saving.value || stale.value) return false;
  if (props.mode === 'edit')
    return Boolean(props.company?.id && form.value.name.trim() && dirty.value);
  if (props.mode === 'unlink') return Boolean(props.company?.id);
  return Boolean(
    selected.value && selected.value.id !== props.contact.company_id
  );
});
const search = async (nextPage = 1) => {
  if (saving.value || props.readOnly || query.value.trim().length < 2) return;
  const term = nextPage === 1 ? query.value.trim() : submittedQuery.value;
  searchError.value = false;
  error.value = '';
  results.value = [];
  if (nextPage === 1) selected.value = null;
  try {
    const response = await request.run(() =>
      CompanyAPI.search(term, nextPage, 'name')
    );
    if (!response) return;
    results.value = response.data.payload;
    total.value = response.data.meta.total_count;
    page.value = nextPage;
    submittedQuery.value = term;
    searched.value = true;
  } catch {
    searchError.value = true;
  }
};
watch(
  query,
  () => {
    request.abort();
    results.value = [];
    selected.value = null;
    searched.value = false;
    searchError.value = false;
  },
  { flush: 'sync' }
);
const save = async () => {
  if (!canSave.value || !formElement.value?.reportValidity()) return;
  const identity = context.value;
  const operation = props.mode;
  saving.value = true;
  error.value = '';
  request.abort();
  try {
    if (operation === 'edit') {
      const patch = Object.fromEntries(
        Object.entries(form.value)
          .filter(([key, value]) => value.trim() !== initial[key].trim())
          .map(([key, value]) => [key, value.trim() || null])
      );
      const { city, ...fields } = patch;
      await companies.update({
        id: props.company.id,
        ...fields,
        ...(Object.hasOwn(patch, 'city')
          ? { additionalAttributes: { city } }
          : {}),
      });
    } else {
      const companyId = operation === 'unlink' ? null : selected.value.id;
      const { data } = await ContactAPI.update(props.contact.id, {
        company_id: companyId,
      });
      // The native endpoint ignores company_id if Companies was disabled meanwhile.
      // Only a response confirming the requested association may announce success.
      if (
        data.payload.id !== props.contact.id ||
        data.payload.company_id !== companyId
      ) {
        if (!disposed && identity === context.value)
          error.value = label('NOT_CONFIRMED');
        return;
      }
    }
    if (!disposed && identity === context.value) emit('saved', operation);
  } catch {
    if (!disposed && identity === context.value)
      error.value = label(operation === 'edit' ? 'EDIT_ERROR' : 'LINK_ERROR');
  } finally {
    if (!disposed) saving.value = false;
  }
};
onBeforeUnmount(() => {
  disposed = true;
});
defineExpose({ dirty, saving, canSave });
</script>

<template>
  <form
    :id="formId"
    ref="formElement"
    class="grid min-w-0 gap-5"
    data-crm-company-form
    @submit.prevent="save"
  >
    <header class="flex items-start gap-3">
      <div
        class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-brand/10 text-n-blue-11"
      >
        <span class="i-lucide-building-2 size-5" aria-hidden="true" />
      </div>
      <div class="min-w-0">
        <h3 class="mb-1 text-base font-semibold text-n-slate-12">
          {{
            label(
              mode === 'edit'
                ? 'EDIT_TITLE'
                : mode === 'unlink'
                  ? 'UNLINK_TITLE'
                  : 'LINK_TITLE'
            )
          }}
        </h3>
        <p class="m-0 break-words text-sm text-n-slate-11">
          {{ mode === 'edit' ? initial.name : contact.name }}
        </p>
      </div>
    </header>
    <p class="m-0 text-sm leading-6 text-n-slate-11">
      {{
        mode === 'edit'
          ? label('EDIT_HELP')
          : t(
              mode === 'unlink'
                ? 'CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.UNLINK_CONTEXT'
                : 'CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.LINK_HELP',
              {
                name: contact.name,
              }
            )
      }}
    </p>
    <p
      v-if="error || stale"
      role="alert"
      class="m-0 rounded-lg bg-n-ruby-3 p-3 text-sm leading-6 text-n-ruby-11"
    >
      {{ stale ? label('STALE') : error }}
    </p>
    <fieldset
      v-if="mode === 'edit'"
      :disabled="saving || readOnly"
      class="m-0 grid min-w-0 gap-4 border-0 p-0"
    >
      <Input
        v-model="form.name"
        :label="label('NAME')"
        :maxlength="100"
        required
      />
      <div class="grid gap-2">
        <Input
          v-model="form.domain"
          :label="label('DOMAIN')"
          :placeholder="label('DOMAIN_PLACEHOLDER')"
        />
        <p class="m-0 text-xs leading-5 text-n-slate-11">
          {{ label('DOMAIN_HELP') }}
        </p>
      </div>
      <Input
        v-model="form.city"
        :label="t('COMPANIES.DETAIL.PROFILE.FIELDS.CITY')"
      />
      <TextArea
        :id="`${formId}-description`"
        v-model="form.description"
        :label="label('DESCRIPTION')"
        :max-length="1000"
        show-character-count
        auto-height
      />
    </fieldset>
    <div
      v-else-if="mode === 'unlink'"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-alpha-black2 p-4"
      data-company-unlink-confirmation
    >
      <p class="m-0 text-xs font-medium text-n-slate-11">
        {{ label('CURRENT') }}
      </p>
      <p class="m-0 break-words text-base font-semibold text-n-slate-12">
        {{ initial.name }}
      </p>
      <p class="m-0 break-all text-sm text-n-slate-11">
        {{ initial.domain || label('NO_DOMAIN') }}
      </p>
      <p
        class="m-0 border-t border-n-weak pt-3 text-sm leading-6 text-n-slate-11"
      >
        {{ label('UNLINK_HELP') }}
      </p>
    </div>
    <template v-else>
      <div class="flex items-end gap-3">
        <Input
          v-model="query"
          class="min-w-0 flex-1"
          type="search"
          :label="label('SEARCH')"
          :placeholder="label('SEARCH_PLACEHOLDER')"
          :disabled="saving || readOnly"
          @keydown.enter.prevent="search(1)"
        />
        <Button
          type="button"
          slate
          faded
          icon="i-lucide-search"
          :label="label('FIND')"
          :disabled="saving || readOnly || query.trim().length < 2"
          :is-loading="request.isPending.value"
          @click="search(1)"
        />
      </div>
      <p v-if="searchError" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ label('SEARCH_ERROR') }}
      </p>
      <p
        v-else-if="request.isPending.value"
        role="status"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ label('LOADING') }}
      </p>
      <div v-else-if="results.length" class="grid gap-3">
        <div
          class="max-h-[18rem] overflow-y-auto rounded-xl border border-n-weak"
          :aria-label="label('RESULTS')"
          role="group"
        >
          <button
            v-for="item in results"
            :key="item.id"
            type="button"
            :disabled="saving || readOnly || item.id === contact.company_id"
            :aria-pressed="selected?.id === item.id"
            class="flex min-h-14 w-full items-center gap-3 border-b border-n-weak p-3 text-start last:border-0 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-n-brand disabled:opacity-50"
            :class="selected?.id === item.id ? 'bg-n-brand/10' : 'bg-n-solid-1'"
            @click="selected = item"
          >
            <span
              class="i-lucide-building-2 size-5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
            <div class="min-w-0 flex-1">
              <div class="break-words text-sm font-medium text-n-slate-12">
                {{ item.name }}
              </div>
              <div class="break-all text-xs text-n-slate-11">
                {{ item.domain || label('NO_DOMAIN') }}
              </div>
            </div>
            <span
              v-if="selected?.id === item.id"
              class="i-lucide-circle-check size-5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
            <div
              v-else-if="item.id === contact.company_id"
              class="text-xs text-n-slate-11"
            >
              {{ label('CURRENT') }}
            </div>
          </button>
        </div>
        <div
          v-if="total > 25"
          class="flex items-center justify-between gap-2 text-xs text-n-slate-11"
        >
          <Button
            type="button"
            sm
            slate
            ghost
            :label="label('PREVIOUS')"
            :disabled="saving || page <= 1"
            @click="search(page - 1)"
          />
          <span>{{
            t('CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.PAGE', {
              page,
              pages: Math.ceil(total / 25),
            })
          }}</span>
          <Button
            type="button"
            sm
            slate
            ghost
            :label="label('NEXT')"
            :disabled="saving || page * 25 >= total"
            @click="search(page + 1)"
          />
        </div>
      </div>
      <p
        v-else
        class="m-0 rounded-lg border border-dashed border-n-strong p-4 text-sm leading-6 text-n-slate-11"
        role="status"
      >
        {{ label(searched ? 'EMPTY' : 'SEARCH_HINT') }}
      </p>
      <div
        v-if="selected"
        class="grid gap-2 rounded-xl bg-n-blue-3 p-4"
        data-company-selection
      >
        <p class="m-0 text-xs font-medium text-n-blue-11">
          {{ label('SELECTED') }}
        </p>
        <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
          {{ selected.name }}
        </p>
        <p class="m-0 break-all text-xs text-n-slate-11">
          {{ selected.domain || label('NO_DOMAIN') }}
        </p>
      </div>
      <p v-if="company" class="m-0 text-xs leading-5 text-n-slate-11">
        {{
          t('CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.REPLACE_HELP', {
            name: company.name,
          })
        }}
      </p>
    </template>
  </form>
</template>
