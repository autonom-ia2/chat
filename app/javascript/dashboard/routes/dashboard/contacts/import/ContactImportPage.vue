<script setup>
// Importar contatos (#1006, PRD §8.7): upload → reading → columns, other columns (contact
// attributes), people, companies → "Importar" → result. Same reading as "Novo público";
// the screen never names the engine that reads the columns (B1a).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import ContactImportsAPI from 'dashboard/api/contactImports';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactImportColumns from 'dashboard/components-next/ContactImport/ContactImportColumns.vue';
import ContactImportCompanies from 'dashboard/components-next/ContactImport/ContactImportCompanies.vue';
import ContactImportProblems from 'dashboard/components-next/ContactImport/ContactImportProblems.vue';
import ContactImportResult from 'dashboard/components-next/ContactImport/ContactImportResult.vue';
import {
  NO_COLUMN,
  stageFor,
  isPolling,
  columnsOf,
  currentMapping,
  sameMapping,
  hasContactColumn,
  mappingPayload,
  companiesAvailable,
  peopleCounts,
  globalErrors,
  formatCount,
} from 'dashboard/components-next/ContactImport/contactImportView';

const POLL_MS = 2000;
const MAX_FILE_MB = 10;
const NS = 'CONTACT_IMPORT_JOURNEY';

const { t, te, locale } = useI18n();
const n = value => formatCount(locale.value, value);
const router = useRouter();

const contactImport = ref(null);
const mapping = ref(currentMapping(null));
const createCompanies = ref(true);
const sending = ref(false);
const errorMessage = ref('');
const fileInput = ref(null);
let pollTimer = null;

const stage = computed(() => (sending.value ? 'reading' : stageFor(contactImport.value)));
const status = computed(() => contactImport.value?.status);
const needsChoice = computed(() => status.value === 'needs_column_choice');
const isReady = computed(() => status.value === 'ready_to_confirm');
const refused = computed(() => status.value === 'validation_failed');
const people = computed(() => peopleCounts(contactImport.value));
const fileErrors = computed(() => (refused.value ? globalErrors(contactImport.value) : []));

const columnsChanged = computed(
  () => !sameMapping(mapping.value, currentMapping(contactImport.value))
);
const canApplyColumns = computed(
  () => (needsChoice.value || columnsChanged.value) && hasContactColumn(mapping.value)
);
const canImport = computed(() => isReady.value && !columnsChanged.value);
const showCompanies = computed(
  () => companiesAvailable(contactImport.value) && mapping.value.company !== NO_COLUMN
);
const companyColumnName = computed(
  () => columnsOf(contactImport.value).find(column => column.index === mapping.value.company)?.header || ''
);

const reasonText = code =>
  te(`${NS}.ERRORS.REASONS.${code}`)
    ? t(`${NS}.ERRORS.REASONS.${code}`)
    : t(`${NS}.ERRORS.GENERIC`);

const stopPolling = () => {
  window.clearTimeout(pollTimer);
  pollTimer = null;
};

const apply = payload => {
  contactImport.value = payload;
  mapping.value = currentMapping(payload);
  createCompanies.value = payload.create_companies !== false;
};

const fail = () => {
  errorMessage.value = t(`${NS}.ERRORS.GENERIC`);
};

const poll = async () => {
  stopPolling();
  if (!isPolling(contactImport.value)) return;
  pollTimer = window.setTimeout(async () => {
    try {
      const { data } = await ContactImportsAPI.show(contactImport.value.id);
      apply(data.payload);
      poll();
    } catch {
      fail();
    }
  }, POLL_MS);
};

const upload = async file => {
  errorMessage.value = '';
  if (file.size > MAX_FILE_MB * 1024 * 1024) {
    errorMessage.value = t(`${NS}.UPLOAD.TOO_LARGE`, { size: MAX_FILE_MB });
    return;
  }
  sending.value = true;
  try {
    const { data } = await ContactImportsAPI.upload(file, {
      createCompanies: createCompanies.value,
    });
    apply(data.payload);
    poll();
  } catch {
    errorMessage.value = t(`${NS}.UPLOAD.ERROR`);
  } finally {
    sending.value = false;
  }
};

const onFileChange = event => {
  const [file] = event.target.files || [];
  if (file) upload(file);
};

const chooseFile = () => fileInput.value?.click();

const applyColumns = async () => {
  errorMessage.value = '';
  try {
    const { data } = await ContactImportsAPI.chooseColumns(
      contactImport.value.id,
      mappingPayload(mapping.value)
    );
    apply(data.payload);
    poll();
  } catch {
    fail();
  }
};

const runImport = async () => {
  errorMessage.value = '';
  try {
    const { data } = await ContactImportsAPI.confirm(contactImport.value.id);
    apply(data.payload);
    poll();
  } catch {
    fail();
  }
};

// The switch is saved as soon as it changes; the preview does not need a new reading.
watch(createCompanies, async value => {
  const current = contactImport.value;
  if (!current || current.create_companies === value) return;
  try {
    const { data } = await ContactImportsAPI.setCompanies(current.id, value);
    contactImport.value = data.payload;
  } catch {
    createCompanies.value = !value;
    fail();
  }
});

const downloadProblems = async () => {
  try {
    const { data } = await ContactImportsAPI.downloadProblems(contactImport.value.id);
    downloadCsvFile(`contatos_${contactImport.value.id}_problemas.csv`, data);
  } catch {
    fail();
  }
};

const startOver = () => {
  stopPolling();
  contactImport.value = null;
  mapping.value = currentMapping(null);
  createCompanies.value = true;
  errorMessage.value = '';
};

const backToContacts = () => router.push({ name: 'contacts_dashboard_index' });

onBeforeUnmount(stopPolling);
</script>

<template>
  <section class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2">
    <div class="mx-auto flex w-full max-w-[60rem] flex-col gap-5 p-4 sm:p-5 lg:p-8">
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
          {{ t(`${NS}.TITLE`) }}
        </span>
      </nav>
      <header class="min-w-0">
        <h1 class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12">
          {{ t(`${NS}.TITLE`) }}
        </h1>
        <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
          {{ stage === 'review' ? t(`${NS}.REVIEW_SUBTITLE`) : t(`${NS}.SUBTITLE`) }}
        </p>
      </header>

      <p
        v-if="errorMessage"
        role="alert"
        class="mb-0 rounded-xl bg-n-ruby-3 px-4 py-3 text-sm text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>

      <div
        v-if="stage === 'upload'"
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
      >
        <input
          ref="fileInput"
          type="file"
          class="sr-only"
          accept=".csv,.xlsx"
          data-test="file-input"
          :aria-label="t(`${NS}.UPLOAD.LABEL`)"
          @change="onFileChange"
        />
        <button
          type="button"
          class="flex min-h-[10.5rem] w-full flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-n-blue-6 bg-n-blue-2 p-6 text-center"
          data-test="drop-zone"
          @click="chooseFile"
        >
          <span class="i-lucide-upload size-6 text-n-blue-11" aria-hidden="true" />
          <strong class="text-sm text-n-slate-12">{{ t(`${NS}.UPLOAD.LABEL`) }}</strong>
          <span class="text-xs text-n-slate-11">
            {{ t(`${NS}.UPLOAD.HINT`, { size: MAX_FILE_MB }) }}
          </span>
        </button>
      </div>

      <div
        v-else-if="stage === 'reading'"
        class="flex items-center justify-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-12 text-sm text-n-slate-11"
        role="status"
        data-test="reading"
      >
        <Spinner />
        {{ sending ? t(`${NS}.UPLOAD.SENDING`) : t(`${NS}.READING`) }}
      </div>

      <template v-else-if="stage === 'review'">
        <div class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm">
          <div
            class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-slate-2 px-4 py-3"
          >
            <div class="min-w-0">
              <strong class="block truncate text-sm text-n-slate-12">
                {{ contactImport.source_filename }}
              </strong>
              <span class="text-xs text-n-slate-11">
                {{ t(`${NS}.FILE.ROWS`, { count: n(contactImport.total_rows || 0) }) }}
              </span>
            </div>
            <Button
              :label="t(`${NS}.FILE.OTHER_FILE`)"
              variant="faded"
              color="slate"
              size="sm"
              class="!min-h-11"
              @click="startOver"
            />
          </div>

          <div v-if="needsChoice" class="rounded-xl bg-n-amber-2 px-4 py-3" data-test="choose-columns">
            <strong class="text-sm text-n-slate-12">{{ t(`${NS}.COLUMNS.CHOOSE_TITLE`) }}</strong>
            <p class="mb-0 text-xs text-n-slate-11">{{ t(`${NS}.COLUMNS.CHOOSE_HINT`) }}</p>
          </div>
          <ul v-if="fileErrors.length" role="alert" class="m-0 list-none rounded-xl bg-n-ruby-3 px-4 py-3 text-sm text-n-ruby-11">
            <li class="font-semibold">{{ t(`${NS}.ERRORS.FILE_REFUSED`) }}</li>
            <li v-for="code in fileErrors" :key="code">{{ reasonText(code) }}</li>
          </ul>

          <ContactImportColumns
            v-model="mapping"
            :contact-import="contactImport"
            :show-attributes="isReady && !columnsChanged"
          />
          <div v-if="needsChoice || columnsChanged" class="flex flex-wrap items-center justify-end gap-3">
            <span v-if="!hasContactColumn(mapping)" class="text-xs text-n-ruby-11">
              {{ t(`${NS}.COLUMNS.NEED_CONTACT`) }}
            </span>
            <Button
              :label="t(`${NS}.COLUMNS.APPLY`)"
              :disabled="!canApplyColumns"
              class="!min-h-11"
              data-test="apply-columns"
              @click="applyColumns"
            />
          </div>

          <template v-if="isReady && !columnsChanged">
            <div class="grid gap-3 md:grid-cols-2">
              <div class="rounded-xl bg-n-teal-3 p-4" data-test="people-ready">
                <p class="mb-0 text-2xl font-semibold tabular-nums text-n-slate-12">{{ n(people.ready) }}</p>
                <strong class="text-sm text-n-slate-12">{{ t(`${NS}.PEOPLE.READY`) }}</strong>
                <p class="mb-0 text-xs text-n-slate-11" data-test="people-split">
                  {{ t(`${NS}.PEOPLE.SPLIT`, { existing: n(people.existing), new: n(people.created) }) }}
                </p>
              </div>
              <ContactImportProblems
                :contact-import="contactImport"
                :reason-text="reasonText"
                @download="downloadProblems"
              />
            </div>
          </template>

          <ContactImportCompanies
            v-if="showCompanies"
            v-model="createCompanies"
            :contact-import="contactImport"
            :column-name="companyColumnName"
          />
        </div>
        <div class="flex flex-wrap justify-between gap-3">
          <Button
            :label="t(`${NS}.ACTIONS.CANCEL`)"
            variant="faded"
            color="slate"
            class="!min-h-11"
            @click="backToContacts"
          />
          <Button
            :label="t(`${NS}.ACTIONS.IMPORT`)"
            :disabled="!canImport"
            class="!min-h-11"
            data-test="import"
            @click="runImport"
          />
        </div>
      </template>

      <div
        v-else-if="stage === 'importing'"
        class="flex items-center justify-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-12 text-sm text-n-slate-11"
        role="status"
        data-test="importing"
      >
        <Spinner />
        {{ t(`${NS}.ACTIONS.IMPORTING`) }}
      </div>

      <ContactImportResult
        v-else-if="stage === 'done'"
        :contact-import="contactImport"
        @see-contacts="backToContacts"
        @new-import="startOver"
        @download="downloadProblems"
      />

      <div
        v-else
        role="alert"
        class="flex flex-col items-start gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
        data-test="failed"
      >
        <p class="mb-0 text-sm text-n-ruby-11">{{ t(`${NS}.ERRORS.IMPORT_FAILED`) }}</p>
        <Button :label="t(`${NS}.ACTIONS.NEW_IMPORT`)" class="!min-h-11" @click="startOver" />
      </div>
    </div>
  </section>
</template>
