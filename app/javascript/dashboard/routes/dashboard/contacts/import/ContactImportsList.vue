<script setup>
// Contatos > Importações (#2771, decision 15): every contact list that came in, from a
// spreadsheet or from the automation step "para cada item" (origin "Automação"). Opening
// one shows its result on the Importar contatos screen. Never Públicos or campaign bases.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import ContactImportsAPI from 'dashboard/api/contactImports';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  stageFor,
  formatCount,
} from 'dashboard/components-next/ContactImport/contactImportView';
import { CONTACT_IMPORT_ROUTE } from './contactImport.routes';

const NS = 'CONTACT_IMPORT_JOURNEY';
const LIST = `${NS}.LIST`;
const DONE_STATUSES = ['completed', 'completed_with_failures'];

const { t, locale } = useI18n();
const router = useRouter();
const n = value => formatCount(locale.value, value);

const imports = ref([]);
const total = ref(0);
const page = ref(0);
const perPage = ref(25);
const loading = ref(false);
const failed = ref(false);

// By page, not by the rows shown: a repeated row is dropped and must not ask for more forever.
const hasMore = computed(
  () => page.value < Math.ceil(total.value / perPage.value)
);

// An import created between two pages shifts the next page by one: the repeated row goes.
const withoutRepeated = (current, incoming) => {
  const seen = new Set(current.map(item => item.id));
  return [...current, ...incoming.filter(item => !seen.has(item.id))];
};

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await ContactImportsAPI.list(page.value + 1);
    imports.value = withoutRepeated(imports.value, data.payload);
    total.value = data.meta.count;
    page.value = data.meta.current_page;
    perPage.value = data.meta.per_page || perPage.value;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

// The file name stays on the import itself (show): the list names a spreadsheet import by its kind.
const titleOf = item =>
  item.origin === 'automation'
    ? item.name || t(`${LIST}.NO_NAME`)
    : t(`${LIST}.FILE_TITLE`);

const statusOf = item => {
  if (DONE_STATUSES.includes(item.status))
    return t(`${LIST}.STATUS.${item.status}`);
  return t(`${LIST}.STATUS.${stageFor(item)}`);
};

const dateOf = item =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(item.created_at));

const openImport = item =>
  router.push({ name: CONTACT_IMPORT_ROUTE, params: { importId: item.id } });
const newImport = () => router.push({ name: CONTACT_IMPORT_ROUTE });
const backToContacts = () => router.push({ name: 'contacts_dashboard_index' });

onMounted(load);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div
      class="mx-auto flex w-full max-w-[60rem] flex-col gap-5 p-4 pb-24 sm:p-5 sm:pb-24 lg:p-8"
    >
      <nav
        class="flex items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t(`${NS}.BREADCRUMB`)"
      >
        <button
          type="button"
          class="min-h-11 text-n-slate-11 hover:text-n-slate-12"
          @click="backToContacts"
        >
          {{ t(`${NS}.CONTACTS`) }}
        </button>
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t(`${LIST}.TITLE`) }}
        </span>
      </nav>
      <header class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <h1
            class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ t(`${LIST}.TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${LIST}.SUBTITLE`) }}
          </p>
        </div>
        <Button
          :label="t(`${LIST}.NEW_IMPORT`)"
          icon="i-lucide-download"
          class="!min-h-11"
          data-test="new-import"
          @click="newImport"
        />
      </header>

      <p
        v-if="failed"
        role="alert"
        class="mb-0 rounded-xl bg-n-ruby-3 px-4 py-3 text-sm text-n-ruby-11"
      >
        {{ t(`${LIST}.ERROR`) }}
      </p>

      <div
        v-if="loading && !imports.length"
        class="flex items-center justify-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-12 text-sm text-n-slate-11"
        role="status"
        data-test="loading"
      >
        <Spinner />
        {{ t(`${LIST}.LOADING`) }}
      </div>

      <p
        v-else-if="!failed && !imports.length"
        class="mb-0 rounded-2xl border border-n-weak bg-n-solid-1 p-8 text-center text-sm text-n-slate-11"
        data-test="empty"
      >
        {{ t(`${LIST}.EMPTY`) }}
      </p>

      <ul
        v-if="imports.length"
        class="m-0 flex list-none flex-col gap-2 p-0"
        data-test="imports"
      >
        <li v-for="item in imports" :key="item.id">
          <button
            type="button"
            class="flex min-h-11 w-full flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 text-start hover:bg-n-alpha-1"
            :aria-label="t(`${LIST}.OPEN`, { name: titleOf(item) })"
            :data-import="item.id"
            @click="openImport(item)"
          >
            <span class="flex min-w-0 flex-col gap-1">
              <span class="flex min-w-0 items-center gap-2">
                <strong class="truncate text-sm text-n-slate-12">
                  {{ titleOf(item) }}
                </strong>
                <span
                  class="shrink-0 rounded-md px-2 py-0.5 text-xs"
                  :class="
                    item.origin === 'automation'
                      ? 'bg-n-iris-3 text-n-iris-11'
                      : 'bg-n-slate-3 text-n-slate-11'
                  "
                  data-test="origin"
                >
                  {{ t(`${LIST}.ORIGIN.${item.origin}`) }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11" data-test="who">
                {{
                  t(`${LIST}.BY`, {
                    date: dateOf(item),
                    name: item.created_by?.name || '',
                  })
                }}
              </span>
            </span>
            <span class="flex flex-col items-end gap-1 text-end">
              <span
                class="text-sm tabular-nums text-n-slate-12"
                data-test="counts"
              >
                {{
                  t(`${LIST}.COUNTS`, {
                    imported: n(item.imported_contacts_count),
                    failed: n(item.failed_count),
                  })
                }}
              </span>
              <span class="text-xs text-n-slate-11" data-test="status">
                {{ statusOf(item) }}
              </span>
            </span>
          </button>
        </li>
      </ul>

      <Button
        v-if="hasMore"
        :label="t(`${LIST}.MORE`)"
        :is-loading="loading"
        variant="faded"
        color="slate"
        class="!min-h-11 self-center"
        data-test="more"
        @click="load"
      />
    </div>
  </section>
</template>
