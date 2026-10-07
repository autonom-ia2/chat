<script setup>
// "Trazer meu modelo" (#1099): brings an e-mail made on another platform into "Meus modelos".
// choose -> source (paste, file or address) -> preparing (the job, followed by polling) -> result
// (before and after, warnings, fixes) -> name -> back to the library with the new card. Errors are
// one sentence and one way out. The import id lives in the address, so leaving and coming back
// resumes it. Everything that changes the design happens on the server.
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
} from 'dashboard/components-next/EmailTemplateImport/importErrors';
import { uniqueName } from 'dashboard/components-next/EmailTemplateImport/uniqueName';

const POLL_MS = 1500;
const LIBRARY = 'campaigns_email_templates';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const screen = ref('loading');
const mode = ref('paste');
const pickedFile = ref(null);
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
let isUnmounted = false;

const importId = ref(Number(route.params.importId) || null);
const errorText = code => t(`EMAIL_IMPORT.ERRORS.${code.toUpperCase()}`);

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
};

const libraryRoute = query => ({
  name: LIBRARY,
  params: {
    accountId: route.params.accountId,
    campaignId: route.query.campaign || undefined,
  },
  query,
});

const fail = (code, file = null) => {
  stopPolling();
  failure.value = {
    ...classifyError(code),
    fileName: file?.name || '',
    fileSize: file?.size || 0,
  };
  screen.value = 'error';
};

const compileResult = async () => {
  isCompiling.value = true;
  const html = await compileEmailMjml(data.value?.result_mjml);
  if (isUnmounted) return;
  resultHtml.value = withImportMarks(html);
  isCompiling.value = false;
};

const showReady = async () => {
  screen.value = 'result';
  await compileResult();
};

const poll = async () => {
  if (!importId.value || isUnmounted) return;
  try {
    const { data: payload } = await EmailCampaignTemplateImportsAPI.show(
      importId.value
    );
    if (isUnmounted) return;
    data.value = payload;
    if (payload.status === 'ready') {
      stopPolling();
      await showReady();
    } else if (payload.status === 'failed') {
      fail(payload.error_code || 'internal');
    } else if (payload.status === 'saved') {
      router.replace(
        libraryRoute({ novo: payload.email_campaign_template_id })
      );
    } else {
      screen.value = 'preparing';
      pollTimer = setTimeout(poll, POLL_MS);
    }
  } catch (error) {
    if (!isUnmounted) fail(errorCode(error) || 'internal');
  }
};

const replaceImportId = id => {
  const params = { ...route.params, importId: id || undefined };
  router.replace({ name: route.name, params, query: route.query });
};

const follow = id => {
  stopPolling();
  importId.value = id;
  replaceImportId(id);
  screen.value = 'preparing';
  poll();
};

const resumeActive = async () => {
  const { data: latest } = await EmailCampaignTemplateImportsAPI.latest();
  const active = latest?.payload?.[0];
  if (active) follow(active.id);
  else fail('in_progress');
};

const clearState = () => {
  stopPolling();
  data.value = null;
  resultHtml.value = '';
  failure.value = null;
  sourceError.value = '';
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

// The page is kept alive between visits: each visit starts from the address — the import it names
// (to follow or see), or a new one.
const start = () => {
  clearState();
  importId.value = Number(route.params.importId) || null;
  if (importId.value) {
    screen.value = 'loading';
    poll();
  } else {
    screen.value = 'choose';
  }
};

const choose = (picked, file = null) => {
  mode.value = picked;
  pickedFile.value = file;
  sourceError.value = '';
  screen.value = 'source';
};

const localProblem = input => {
  if (input.kind === 'file') return fileProblem(input.file);
  if (input.kind === 'paste') return pasteProblem(input.content);
  return '';
};

const submit = async input => {
  lastInput.value = input;
  sourceError.value = '';
  const problem = localProblem(input);
  if (problem) {
    const { kind } = classifyError(problem);
    if (kind === 'inline') sourceError.value = errorText(problem);
    else fail(problem, input.file);
    return;
  }
  isSending.value = true;
  try {
    const { data: payload } =
      await EmailCampaignTemplateImportsAPI.start(input);
    data.value = payload;
    follow(payload.id);
  } catch (error) {
    const code = errorCode(error) || 'internal';
    if (code === 'in_progress') await resumeActive();
    else if (classifyError(code).kind === 'inline')
      sourceError.value = errorText(code);
    else fail(code, input.file);
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
  isFixing.value = true;
  fixError.value = '';
  try {
    const { data: payloadAfter } = await EmailCampaignTemplateImportsAPI.fix(
      importId.value,
      payload
    );
    data.value = payloadAfter;
    fixDialog.value?.close();
    await compileResult();
  } catch (error) {
    fixError.value = errorText(errorCode(error) || 'fix_invalid');
  } finally {
    isFixing.value = false;
  }
};

const toName = async () => {
  nameError.value = '';
  screen.value = 'name';
  const base =
    data.value?.report?.title || t('EMAIL_IMPORT.SCREEN.NAME.FALLBACK');
  try {
    const { data: templates } = await EmailCampaignTemplatesAPI.index();
    const list = Array.isArray(templates) ? templates : templates.payload || [];
    suggestion.value = uniqueName(
      base,
      list.filter(item => item.account_id !== null).map(item => item.name)
    );
  } catch (error) {
    suggestion.value = base;
  }
};

const save = async name => {
  isSaving.value = true;
  nameError.value = '';
  try {
    const { data: template } = await EmailCampaignTemplateImportsAPI.save(
      importId.value,
      name
    );
    router.push(libraryRoute({ novo: template.id }));
  } catch (error) {
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

let isMounted = false;
onMounted(() => {
  start();
  isMounted = true;
});
onActivated(() => {
  if (isMounted) start();
});
onDeactivated(stopPolling);

onBeforeUnmount(() => {
  isUnmounted = true;
  stopPolling();
});
</script>

<template>
  <section
    class="flex h-full min-w-0 flex-1 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <p class="mb-5 flex items-center gap-2 text-xs text-n-slate-11">
        <button class="min-h-9" @click="goLibrary">
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
        @see="showReady"
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
