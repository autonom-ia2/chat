<script setup>
import { computed, ref, watch, onBeforeUnmount, useId } from 'vue';
import axios from 'dashboard/api/relationships';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import MediaThumbnail from './MediaThumbnail.vue';
import MediaContactSelect from './MediaContactSelect.vue';
import CompanyMediaActions from './CompanyMediaActions.vue';
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  mediaTypeKey,
  formatMediaSize,
  formatMediaDate,
  mediaContactGroups,
} from './mediaPresentation';

const props = defineProps({
  companyId: { type: Number, default: null },
  contactId: { type: Number, default: null },
  expanded: { type: Boolean, default: false },
});
const emit = defineEmits(['expand', 'collapse']);
const { accountId } = useAccount();
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const rows = ref([]);
const inputId = useId();
let actionGeneration = 0;
const contactQuery = ref('');
const contactOptions = ref([]);
const contactLoading = ref(false);
const contactError = ref(false);
const actionError = ref(null);
const showFilters = ref(false);
let contactGeneration = 0;
const total = ref(0);
const loading = ref(false);
const error = ref(false);
const cleanFilters = () => ({
  q: '',
  contact_id: '',
  type: '',
  from: '',
  to: '',
  group: '',
  page: 1,
});
const filters = ref(cleanFilters());
const appliedFilters = ref(cleanFilters());
const hasFilters = computed(() =>
  Object.entries(appliedFilters.value).some(
    ([key, value]) => !['page', 'group'].includes(key) && value !== ''
  )
);
const hasDraftFilters = computed(() =>
  Object.entries(filters.value).some(
    ([key, value]) => key !== 'page' && value !== ''
  )
);
const pageSize = computed(() => (props.expanded ? 25 : 5));
const pageCount = computed(() =>
  Math.max(1, Math.ceil(total.value / pageSize.value))
);
const groups = computed(() =>
  mediaContactGroups(rows.value, appliedFilters.value.group === 'contact')
);
const headers = computed(() =>
  [
    'NAME',
    'CONTACTS',
    'TYPE',
    'MEDIA.SIZE',
    'MEDIA.SENDER',
    'MEDIA.DATE',
    'MEDIA.ACTIONS',
  ].map(key => t(`RELATIONSHIPS.${key}`))
);
let generation = 0;
const base = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/${props.contactId ? 'contacts' : 'companies'}/${props.contactId || props.companyId}/media`
);
const options = computed(() => [
  { value: '', label: t('RELATIONSHIPS.MEDIA.ALL_TYPES') },
  ...['image', 'video', 'audio', 'file'].map(value => ({
    value,
    label: t(`RELATIONSHIPS.MEDIA.${value}`),
  })),
]);
const findContacts = async (query = contactQuery.value) => {
  contactQuery.value = query;
  contactLoading.value = true;
  contactError.value = false;
  contactOptions.value = [];
  contactGeneration += 1;
  const current = contactGeneration;
  try {
    const { data } = await axios.get(`${base.value}/contacts`, {
      params: { q: contactQuery.value },
    });
    if (current === contactGeneration)
      contactOptions.value = data.map(contact => ({
        value: String(contact.id),
        label: contact.name,
      }));
  } catch {
    if (current === contactGeneration) contactError.value = true;
  } finally {
    if (current === contactGeneration) contactLoading.value = false;
  }
};
const load = async () => {
  actionGeneration += 1;
  actionError.value = null;
  generation += 1;
  const current = generation;
  loading.value = true;
  error.value = false;
  rows.value = [];
  total.value = 0;
  try {
    const { data } = await axios.get(base.value, {
      params: {
        ...Object.fromEntries(
          Object.entries(appliedFilters.value).filter(
            ([, value]) => value !== ''
          )
        ),
        per_page: pageSize.value,
        page: props.expanded ? appliedFilters.value.page : 1,
      },
    });
    if (current !== generation) return;
    rows.value = data.payload;
    total.value = data.meta.total;
  } catch {
    if (current === generation) error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
const apply = () => {
  filters.value.page = 1;
  appliedFilters.value = { ...filters.value };
  router.replace({
    query: { ...route.query, media: JSON.stringify(appliedFilters.value) },
  });
  load();
};
const changePage = amount => {
  appliedFilters.value.page += amount;
  filters.value.page = appliedFilters.value.page;
  router.replace({
    query: { ...route.query, media: JSON.stringify(appliedFilters.value) },
  });
  load();
};
const closeContacts = () => {
  contactGeneration += 1;
  contactQuery.value = '';
  contactLoading.value = false;
  contactError.value = false;
};
watch(showFilters, open => {
  if (!open) closeContacts();
});
const clear = () => {
  filters.value = cleanFilters();
  showFilters.value = false;
  contactOptions.value = [];
  closeContacts();
  apply();
};
const openAll = () => {
  if (props.contactId) {
    emit('expand');
    return;
  }
  router.push({
    name: 'relationships_company_media',
    params: { accountId: accountId.value, companyId: props.companyId },
    query: { media: JSON.stringify(appliedFilters.value) },
  });
};
const openOrigin = row =>
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: row.conversation_id,
    },
    query: { messageId: row.message_id },
  });
const download = async (row, inline = false) => {
  actionError.value = null;
  const current = actionGeneration;
  const context = base.value;
  try {
    const { data } = await axios.get(`${base.value}/${row.id}`, {
      params: { inline },
    });
    if (current !== actionGeneration || context !== base.value) return;
    const url = new URL(data.url);
    if (!['http:', 'https:'].includes(url.protocol)) return;
    const link = document.createElement('a');
    link.href = data.url;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.click();
  } catch {
    if (current === actionGeneration && context === base.value)
      actionError.value = { row, inline };
  }
};

watch(
  () => [accountId.value, props.companyId, props.contactId],
  () => {
    contactGeneration += 1;
    contactOptions.value = [];
    contactQuery.value = '';
    if (!props.contactId) findContacts();
    filters.value = cleanFilters();
    if (typeof route.query.media === 'string') {
      try {
        const parsed = JSON.parse(route.query.media);
        Object.keys(filters.value).forEach(key => {
          if (typeof parsed?.[key] === typeof filters.value[key])
            filters.value[key] = parsed[key];
        });
      } catch {
        /* Invalid bookmark uses clean filters. */
      }
    }
    if (props.contactId) {
      filters.value.contact_id = '';
      filters.value.group = '';
    }
    appliedFilters.value = { ...filters.value };
    showFilters.value = ['contact_id', 'type', 'from', 'to', 'group'].some(
      key => filters.value[key] !== ''
    );
    load();
  },
  { immediate: true, flush: 'sync' }
);
watch(
  () => props.expanded,
  () => {
    filters.value.page = 1;
    appliedFilters.value.page = 1;
    load();
  }
);
onBeforeUnmount(() => {
  actionGeneration += 1;
  generation += 1;
  contactGeneration += 1;
});
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-4"
    :class="expanded && !contactId ? 'py-4' : 'p-4'"
  >
    <header class="flex min-w-0 flex-wrap items-start justify-between gap-2">
      <div class="min-w-0">
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{
            t(
              props.contactId
                ? 'RELATIONSHIPS.MEDIA.CONTACT_TITLE'
                : 'RELATIONSHIPS.MEDIA.TITLE'
            )
          }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ t('RELATIONSHIPS.MEDIA.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="contactId && expanded"
        type="button"
        sm
        ghost
        class="min-h-11"
        icon="i-lucide-arrow-left"
        :label="t('RELATIONSHIPS.BACK')"
        @click="emit('collapse')"
      />
      <Button
        v-if="!expanded"
        type="button"
        sm
        ghost
        class="min-h-11 shrink-0"
        icon="i-lucide-expand"
        :label="t('RELATIONSHIPS.MEDIA.ALL')"
        @click="openAll"
      />
    </header>
    <form class="flex min-w-0 flex-col gap-3" @submit.prevent="apply">
      <Input
        v-model="filters.q"
        type="search"
        :aria-label="t('RELATIONSHIPS.MEDIA.SEARCH')"
        :placeholder="t('RELATIONSHIPS.MEDIA.SEARCH')"
        custom-input-class="!ps-10"
      >
        <template #prefix>
          <span
            class="pointer-events-none absolute start-3 top-3 i-lucide-search size-4 text-n-slate-10"
            aria-hidden="true"
          />
        </template>
      </Input>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          sm
          slate
          outline
          class="min-h-11"
          icon="i-lucide-sliders-horizontal"
          :label="t('RELATIONSHIPS.MEDIA.FILTERS')"
          :aria-expanded="showFilters"
          :aria-controls="`${inputId}-filters`"
          @click="showFilters = !showFilters"
        />
        <Button
          type="submit"
          sm
          class="min-h-11"
          :label="t('RELATIONSHIPS.MEDIA.FILTER')"
        />
        <Button
          v-if="hasDraftFilters || hasFilters"
          type="button"
          sm
          ghost
          slate
          class="min-h-11"
          :label="t('RELATIONSHIPS.MEDIA.CLEAR')"
          @click="clear"
        />
      </div>
      <div
        v-if="showFilters"
        :id="`${inputId}-filters`"
        class="grid min-w-0 grid-cols-1 gap-3 rounded-xl border border-n-weak bg-n-alpha-black2 p-3"
        :class="{ 'md:grid-cols-2 xl:grid-cols-4': expanded && !contactId }"
      >
        <label
          class="flex min-w-0 flex-col gap-2 text-xs font-medium text-n-slate-11"
        >
          {{ t('RELATIONSHIPS.TYPE') }}
          <ChoiceSelect
            v-model="filters.type"
            :options="options"
            :aria-label="t('RELATIONSHIPS.TYPE')"
            class="min-w-0"
          />
        </label>
        <div v-if="!contactId" class="flex min-w-0 flex-col gap-2">
          <span class="text-xs font-medium text-n-slate-11">{{
            t('RELATIONSHIPS.CONTACTS')
          }}</span>
          <MediaContactSelect
            :key="base"
            v-model="filters.contact_id"
            :options="contactOptions"
            :loading="contactLoading"
            :error="contactError"
            @search="findContacts"
            @retry="findContacts()"
            @close="closeContacts"
          />
        </div>
        <label
          :for="`${inputId}-from`"
          class="flex min-w-0 flex-col gap-2 text-xs font-medium text-n-slate-11"
        >
          {{ t('RELATIONSHIPS.MEDIA.FROM') }}
          <Input :id="`${inputId}-from`" v-model="filters.from" type="date" />
        </label>
        <label
          :for="`${inputId}-to`"
          class="flex min-w-0 flex-col gap-2 text-xs font-medium text-n-slate-11"
        >
          {{ t('RELATIONSHIPS.MEDIA.TO') }}
          <Input :id="`${inputId}-to`" v-model="filters.to" type="date" />
        </label>
        <p class="col-span-full m-0 text-xs text-n-slate-11">
          {{ t('RELATIONSHIPS.MEDIA.FILTER_TIMEZONE') }}
        </p>
        <label
          v-if="expanded && !contactId"
          class="col-span-full flex min-h-11 items-center gap-2 text-sm text-n-slate-12"
        >
          <input
            v-model="filters.group"
            type="checkbox"
            true-value="contact"
            false-value=""
            class="m-0"
          />
          <span>{{ t('RELATIONSHIPS.MEDIA.GROUP') }}</span>
        </label>
        <Button
          type="submit"
          sm
          class="min-h-11 justify-self-start"
          :label="t('RELATIONSHIPS.MEDIA.APPLY')"
        />
      </div>
    </form>
    <div
      v-if="loading"
      role="status"
      class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-11"
    >
      <Spinner />{{ t('RELATIONSHIPS.LOADING') }}
    </div>
    <div
      v-else-if="error"
      role="alert"
      class="rounded-xl border border-n-weak p-4 text-sm text-n-slate-11"
    >
      <p>{{ t('RELATIONSHIPS.MEDIA.LOAD_ERROR') }}</p>
      <Button
        type="button"
        sm
        faded
        :label="t('RELATIONSHIPS.RETRY')"
        @click="load"
      />
    </div>
    <div
      v-else-if="!rows.length"
      role="status"
      class="flex flex-col items-center gap-2 rounded-xl border border-dashed border-n-weak px-4 py-8 text-center"
    >
      <span
        class="size-7 text-n-slate-10"
        :class="hasFilters ? 'i-lucide-search' : 'i-lucide-folder-open'"
        aria-hidden="true"
      />
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{
          t(
            hasFilters
              ? 'RELATIONSHIPS.MEDIA.NO_RESULTS'
              : 'RELATIONSHIPS.MEDIA.EMPTY'
          )
        }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">
        {{
          t(
            hasFilters
              ? 'RELATIONSHIPS.MEDIA.NO_RESULTS_HINT'
              : contactId
                ? 'RELATIONSHIPS.MEDIA.CONTACT_EMPTY_HINT'
                : 'RELATIONSHIPS.MEDIA.EMPTY_HINT'
          )
        }}
      </p>
    </div>
    <template v-else>
      <div
        v-if="expanded && !contactId"
        class="min-w-0 overflow-x-auto rounded-xl border border-n-weak px-3"
      >
        <BaseTable :headers="headers" :items="rows" class="text-sm">
          <template #row>
            <template v-for="group in groups" :key="group.key">
              <tr
                v-if="appliedFilters.group === 'contact'"
                data-media-group
                class="bg-n-alpha-black2"
              >
                <th
                  colspan="7"
                  scope="rowgroup"
                  class="px-3 py-3 text-start text-sm font-semibold text-n-slate-12"
                >
                  <div class="flex min-w-0 items-center gap-2">
                    <span
                      class="i-lucide-user-round size-4 shrink-0"
                      aria-hidden="true"
                    />
                    <span
                      class="block max-w-xs truncate"
                      :title="group.contact.name"
                    >
                      {{ group.contact.name }}
                    </span>
                  </div>
                </th>
              </tr>
              <tr v-for="row in group.rows" :key="row.id" data-media-row>
                <td class="py-3 pe-4">
                  <div class="flex min-w-0 items-center gap-3">
                    <MediaThumbnail
                      :url="`${base}/${row.id}/preview`"
                      :name="row.filename"
                      :type="row.file_type"
                      class="rounded-lg bg-n-alpha-black2"
                    />
                    <span
                      class="block w-48 truncate font-medium text-n-slate-12"
                      :title="row.filename"
                    >
                      {{ row.filename }}
                    </span>
                  </div>
                </td>
                <td class="py-3 pe-4">
                  <RouterLink
                    :to="{
                      name: 'contacts_edit',
                      params: { accountId, contactId: row.contact.id },
                    }"
                    class="block max-w-40 truncate text-n-blue-11 hover:underline"
                    :title="row.contact.name"
                  >
                    {{ row.contact.name }}
                  </RouterLink>
                </td>
                <td class="py-3 pe-4">
                  <span
                    class="whitespace-nowrap rounded-md bg-n-alpha-black2 px-2 py-1 text-xs font-medium text-n-slate-12"
                  >
                    {{ t(`RELATIONSHIPS.MEDIA.${mediaTypeKey(row)}`) }}
                  </span>
                </td>
                <td class="whitespace-nowrap py-3 pe-4 tabular-nums">
                  {{ formatMediaSize(row.byte_size, locale) }}
                </td>
                <td class="py-3 pe-4">
                  <span
                    class="block max-w-40 truncate"
                    :title="row.sender?.name"
                  >
                    {{ row.sender?.name || t('RELATIONSHIPS.EMPTY') }}
                  </span>
                </td>
                <td class="whitespace-nowrap py-3 pe-4">
                  <time :datetime="row.created_at">{{
                    formatMediaDate(row.created_at, locale)
                  }}</time>
                </td>
                <td class="py-3">
                  <CompanyMediaActions
                    @preview="download(row, true)"
                    @download="download(row)"
                    @origin="openOrigin(row)"
                  />
                </td>
              </tr>
            </template>
          </template>
        </BaseTable>
      </div>
      <ul
        v-else
        class="m-0 flex min-w-0 list-none flex-col divide-y divide-n-weak p-0"
      >
        <li
          v-for="row in rows"
          :key="row.id"
          class="flex min-w-0 gap-3 py-4 first:pt-0"
        >
          <MediaThumbnail
            :url="`${base}/${row.id}/preview`"
            :name="row.filename"
            :type="row.file_type"
            class="rounded-lg bg-n-alpha-black2"
          />
          <div class="min-w-0 flex-1">
            <p
              class="m-0 truncate text-sm font-medium text-n-slate-12"
              :title="row.filename"
            >
              {{ row.filename }}
            </p>
            <p class="mb-1 mt-1 text-xs text-n-slate-11">
              {{
                t('RELATIONSHIPS.MEDIA.METADATA', {
                  type: t(`RELATIONSHIPS.MEDIA.${mediaTypeKey(row)}`),
                  size: formatMediaSize(row.byte_size, locale),
                })
              }}
            </p>
            <RouterLink
              class="block truncate text-xs text-n-blue-11 hover:underline"
              :title="row.contact.name"
              :to="{
                name: 'contacts_edit',
                params: { accountId, contactId: row.contact.id },
              }"
            >
              {{ row.contact.name }}
            </RouterLink>
            <time
              :datetime="row.created_at"
              class="mt-1 block text-xs text-n-slate-11"
              >{{ formatMediaDate(row.created_at, locale) }}</time
            >
            <CompanyMediaActions
              class="mt-2"
              @preview="download(row, true)"
              @download="download(row)"
              @origin="openOrigin(row)"
            />
          </div>
        </li>
      </ul>
    </template>
    <div
      v-if="actionError"
      role="alert"
      class="rounded-lg border border-n-weak p-3 text-sm text-n-slate-11"
    >
      <p>{{ t('RELATIONSHIPS.MEDIA.ACTION_ERROR') }}</p>
      <Button
        type="button"
        sm
        faded
        :label="t('RELATIONSHIPS.RETRY')"
        @click="download(actionError.row, actionError.inline)"
      />
    </div>
    <footer
      v-if="!loading && !error && total"
      class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-3 text-xs text-n-slate-11"
    >
      <span>{{
        t('RELATIONSHIPS.MEDIA.RESULT_COUNT', { shown: rows.length, total })
      }}</span>
      <div v-if="expanded" class="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          sm
          faded
          class="min-h-11"
          :disabled="appliedFilters.page <= 1"
          :label="t('RELATIONSHIPS.BACK')"
          @click="changePage(-1)"
        />
        <span>{{
          t('RELATIONSHIPS.MEDIA.PAGE_COUNT', {
            page: appliedFilters.page,
            pages: pageCount,
          })
        }}</span>
        <Button
          type="button"
          sm
          faded
          class="min-h-11"
          :disabled="appliedFilters.page >= pageCount"
          :label="t('RELATIONSHIPS.NEXT')"
          @click="changePage(1)"
        />
      </div>
    </footer>
    <p class="m-0 text-xs leading-relaxed text-n-slate-11">
      {{ t('RELATIONSHIPS.MEDIA.SCOPE') }}
    </p>
    <p v-if="expanded" class="m-0 text-xs text-n-slate-11">
      {{ t('RELATIONSHIPS.MEDIA.LOCAL_TIMEZONE') }}
    </p>
  </section>
</template>
