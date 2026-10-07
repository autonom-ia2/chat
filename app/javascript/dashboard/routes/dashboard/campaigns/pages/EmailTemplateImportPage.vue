<script setup>
// "Trazer meu modelo" (#1099): brings an e-mail made on another platform into "Meus modelos".
// choose -> source (paste, file or address) -> preparing (the job, followed by polling) -> result
// (before and after, warnings, fixes) -> name -> back to the library with the new card. Errors are
// one sentence and one way out. The import id lives in the address, so leaving and coming back
// resumes it. Everything that changes the design happens on the server.
// The page is kept alive: an answer that arrives after it left (or after it started over) belongs
// to a visit that is over, so it is dropped (`isActive`, `visit` and the import id).
import {
  onActivated,
  onBeforeUnmount,
  onDeactivated,
  onMounted,
  ref,
  useTemplateRef,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmailCampaignTemplatesAPI from 'dashboard/api/emailCampaignTemplates';
import EmailCampaignTemplateImportsAPI from 'dashboard/api/emailCampaignTemplateImports';
import {
  compileEmailMjml,
  withImportMarks,
} from 'dashboard/helper/compileEmailMjml';
import ImportChoose from 'dashboard/components-next/EmailTemplateImport/ImportChoose.vue';
import ImportSource from 'dashboard/components-next/EmailTemplateImport/ImportSource.vue';
import ImportPreparing from 'dashboard/components-next/EmailTemplateImport/ImportPreparing.vue';
import ImportResult from 'dashboard/components-next/EmailTemplateImport/ImportResult.vue';
import ImportFixDialog from 'dashboard/components-next/EmailTemplateImport/ImportFixDialog.vue';
import ImportName from 'dashboard/components-next/EmailTemplateImport/ImportName.vue';
import ImportError from 'dashboard/components-next/EmailTemplateImport/ImportError.vue';
import {
  classifyError,
  errorCode,
  fileProblem,
  pasteProblem,
  sourceOf,
} from 'dashboard/components-next/EmailTemplateImport/importErrors';
import { uniqueName } from 'dashboard/components-next/EmailTemplateImport/uniqueName';

const POLL_MS = 1500;
// A network hiccup is not a failed import: the job goes on in the server.
const MAX_POLL_MISSES = 3;
const LIBRARY = 'campaigns_email_templates';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const screen = ref('loading');
const mode = ref('paste');
const pickedFile = ref(null);
const sourceInput = ref(null);
const data = ref(null);
const resultHtml = ref('');
const isCompiling = ref(false);
const isSending = ref(false);
const sourceError = ref('');
const failure = ref(null);
const lastInput = ref(null);
const activeProblem = ref(null);
const isFixing = ref(false);
const fixError = ref('');
const suggestion = ref('');
const nameError = ref('');
const isSaving = ref(false);
const fixDialog = useTemplateRef('fixDialog');

let pollTimer = null;
let pollMisses = 0;
let isActive = false;
let visit = 0;

const importId = ref(Number(route.params.importId) || null);
const errorText = code => t(`EMAIL_IMPORT.ERRORS.${code.toUpperCase()}`);
const markLabels = () => ({
  unresolved: t('EMAIL_IMPORT.SCREEN.RESULT.MARK_PART'),
  missing: t('EMAIL_IMPORT.SCREEN.RESULT.MARK_IMAGE'),
});

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

// Ends the current visit: whatever it is still waiting for is dropped when it arrives.
const endVisit = () => {
  stopPolling();
  pollMisses = 0;
  visit += 1;
};

const isCurrent = (run, id = importId.value) =>
  isActive && run === visit && id === importId.value;

const libraryRoute = query => ({
  name: LIBRARY,
  params: {
    accountId: route.params.accountId,
    campaignId: route.query.campaign || undefined,
  },
  query,
});

const replaceImportId = id => {
  const params = { ...route.params, importId: id || undefined };
  router.replace({ name: route.name, params, query: route.query });
};

const fail = (code, file = null) => {
  endVisit();
  failure.value = {
    ...classifyError(code),
    source: sourceOf(lastInput.value?.kind || data.value?.source_kind),
    fileName: file?.name || '',
    fileSize: file?.size || 0,
  };
  screen.value = 'error';
};

// A problem with what the person typed (the address that did not open) goes back under the field,
// with what they typed still there.
const backToSource = code => {
  endVisit();
  importId.value = null;
  replaceImportId(null);
  mode.value = lastInput.value.kind;
  sourceInput.value = lastInput.value;
  sourceError.value = errorText(code);
  screen.value = 'source';
};

const failImport = code => {
  if (classifyError(code).kind === 'inline' && lastInput.value) {
    backToSource(code);
  } else {
    fail(code, lastInput.value?.file);
  }
};

const compileResult = async () => {
  const run = visit;
  isCompiling.value = true;
  const html = await compileEmailMjml(data.value?.result_mjml);
  if (!isCurrent(run)) return;
  resultHtml.value = withImportMarks(html, markLabels());
  isCompiling.value = false;
};

const showReady = async () => {
  screen.value = 'result';
  await compileResult();
};

const schedulePoll = poll => {
  stopPolling();
  pollTimer = setTimeout(poll, POLL_MS);
};

const settle = payload => {
  data.value = payload;
  if (payload.status === 'ready') {
    stopPolling();
    showReady();
  } else if (payload.status === 'failed') {
    failImport(payload.error_code || 'internal');
  } else if (payload.status === 'saved') {
    endVisit();
    router.replace(libraryRoute({ novo: payload.email_campaign_template_id }));
  } else {
    screen.value = 'preparing';
    return true;
  }
  return false;
};

const poll = async () => {
  const run = visit;
  const id = importId.value;
  if (!id || !isActive) return;
  try {
    const { data: payload } = await EmailCampaignTemplateImportsAPI.show(id);
    if (!isCurrent(run, id) || payload?.id !== id) return;
    pollMisses = 0;
    if (settle(payload)) schedulePoll(poll);
  } catch (error) {
    if (!isCurrent(run, id)) return;
    const code = errorCode(error);
    if (!code && pollMisses < MAX_POLL_MISSES) {
      pollMisses += 1;
      schedulePoll(poll);
      return;
    }
    fail(code || 'internal');
  }
};

const follow = id => {
  endVisit();
  importId.value = id;
  replaceImportId(id);
  screen.value = 'preparing';
  poll();
};

const resumeActive = async () => {
  const run = visit;
  const { data: latest } = await EmailCampaignTemplateImportsAPI.latest();
  if (!isCurrent(run)) return;
  const active = latest?.payload?.[0];
  if (active) follow(active.id);
  else fail('in_progress');
};

const clearState = () => {
  endVisit();
  data.value = null;
  resultHtml.value = '';
  failure.value = null;
  sourceError.value = '';
  sourceInput.value = null;
  activeProblem.value = null;
  suggestion.value = '';
  nameError.value = '';
  pickedFile.value = null;
  importId.value = null;
};

const reset = () => {
  clearState();
  replaceImportId(null);
  screen.value = 'choose';
};

// Each visit starts from the address — the import it names (to follow or see), or a new one.
const start = () => {
  isActive = true;
  clearState();
  importId.value = Number(route.params.importId) || null;
  if (importId.value) {
    screen.value = 'loading';
    poll();
  } else {
    screen.value = 'choose';
  }
};

const leave = () => {
  isActive = false;
  endVisit();
};

const choose = (picked, file = null) => {
  mode.value = picked;
  pickedFile.value = file;
  sourceInput.value = null;
  sourceError.value = '';
  screen.value = 'source';
};

const localProblem = input => {
  if (input.kind === 'file') return fileProblem(input.file);
  if (input.kind === 'paste') return pasteProblem(input.content);
  return '';
};

const sendFailed = async (code, input) => {
  if (code === 'in_progress') await resumeActive();
  else if (classifyError(code).kind === 'inline')
    sourceError.value = errorText(code);
  else fail(code, input.file);
};

const submit = async input => {
  const run = visit;
  lastInput.value = input;
  sourceError.value = '';
  const problem = localProblem(input);
  if (problem) {
    if (classifyError(problem).kind === 'inline')
      sourceError.value = errorText(problem);
    else fail(problem, input.file);
    return;
  }
  isSending.value = true;
  try {
    const { data: payload } =
      await EmailCampaignTemplateImportsAPI.start(input);
    if (!isCurrent(run)) return;
    data.value = payload;
    follow(payload.id);
  } catch (error) {
    if (isCurrent(run)) await sendFailed(errorCode(error) || 'internal', input);
  } finally {
    isSending.value = false;
  }
};

const retry = () => {
  if (!lastInput.value) {
    reset();
    return;
  }
  screen.value = 'source';
  submit(lastInput.value);
};

const act = problem => {
  if (problem.type === 'invalid') {
    reset();
    return;
  }
  fixError.value = '';
  activeProblem.value = problem;
};

const closeFix = () => {
  activeProblem.value = null;
  fixError.value = '';
};

const fix = async payload => {
  const run = visit;
  isFixing.value = true;
  fixError.value = '';
  try {
    const { data: payloadAfter } = await EmailCampaignTemplateImportsAPI.fix(
      importId.value,
      payload
    );
    if (!isCurrent(run)) return;
    data.value = payloadAfter;
    fixDialog.value?.close();
    await compileResult();
  } catch (error) {
    if (isCurrent(run))
      fixError.value = errorText(errorCode(error) || 'fix_invalid');
  } finally {
    isFixing.value = false;
  }
};

const toName = async () => {
  const run = visit;
  nameError.value = '';
  screen.value = 'name';
  const base =
    data.value?.report?.title || t('EMAIL_IMPORT.SCREEN.NAME.FALLBACK');
  try {
    const { data: templates } = await EmailCampaignTemplatesAPI.index();
    if (!isCurrent(run)) return;
    const list = Array.isArray(templates) ? templates : templates.payload || [];
    suggestion.value = uniqueName(
      base,
      list.filter(item => item.account_id !== null).map(item => item.name)
    );
  } catch (error) {
    if (isCurrent(run)) suggestion.value = base;
  }
};

const save = async name => {
  const run = visit;
  isSaving.value = true;
  nameError.value = '';
  try {
    const { data: template } = await EmailCampaignTemplateImportsAPI.save(
      importId.value,
      name
    );
    if (!isCurrent(run)) return;
    router.push(libraryRoute({ novo: template.id }));
  } catch (error) {
    if (!isCurrent(run)) return;
    const code = errorCode(error) || 'internal';
    if (code === 'blocked' || code === 'not_ready') {
      screen.value = 'loading';
      await poll();
    } else {
      nameError.value = errorText(code);
    }
  } finally {
    isSaving.value = false;
  }
};

const goLibrary = () => router.push(libraryRoute({}));

// Kept alive, the page is also "activated" right after it mounts: that first time is the same visit.
let wasActivated = false;
onMounted(start);
onActivated(() => {
  if (wasActivated) start();
  wasActivated = true;
});
onDeactivated(leave);
onBeforeUnmount(leave);
</script>

<template>
  <section
    class="flex h-full min-w-0 flex-1 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <p class="mb-5 flex items-center gap-2 text-xs text-n-slate-11">
        <button class="min-h-11" @click="goLibrary">
          {{ t('CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE.CAMPAIGNS') }}
        </button>
        <span class="i-lucide-chevron-right size-3.5" />
        {{ t('EMAIL_IMPORT.SCREEN.CRUMB') }}
      </p>

      <div v-if="screen === 'loading'" class="flex justify-center py-16">
        <Spinner />
      </div>
      <ImportChoose
        v-else-if="screen === 'choose'"
        @choose="choose"
        @cancel="goLibrary"
      />
      <ImportSource
        v-else-if="screen === 'source'"
        :mode="mode"
        :initial-file="pickedFile"
        :initial-input="sourceInput"
        :error-text="sourceError"
        :is-sending="isSending"
        @submit="submit"
        @back="screen = 'choose'"
      />
      <ImportPreparing
        v-else-if="screen === 'preparing'"
        :progress="data?.progress || {}"
        :status="data?.status || 'queued'"
        @leave="goLibrary"
      />
      <ImportResult
        v-else-if="screen === 'result' && data"
        :data="data"
        :result-html="resultHtml"
        :is-compiling="isCompiling"
        @act="act"
        @continue="toName"
        @another="reset"
      />
      <ImportName
        v-else-if="screen === 'name'"
        :suggestion="suggestion"
        :html="resultHtml"
        :error-text="nameError"
        :is-saving="isSaving"
        @save="save"
        @back="screen = 'result'"
      />
      <ImportError
        v-else-if="screen === 'error' && failure"
        :kind="failure.kind === 'inline' ? 'other' : failure.kind"
        :code="failure.code"
        :source="failure.source"
        :file-name="failure.fileName"
        :file-size="failure.fileSize"
        @other="reset"
        @retry="retry"
      />
    </div>
    <ImportFixDialog
      ref="fixDialog"
      :problem="activeProblem"
      :is-busy="isFixing"
      :error-text="fixError"
      @fix="fix"
      @close="closeFix"
      @restart="reset"
    />
  </section>
</template>
