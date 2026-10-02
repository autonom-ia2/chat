<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import HandoffRuleFields from './components/HandoffRuleFields.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const SELECTOR_MODES = ['round_robin', 'direct'];
const FLOW_MODES = ['r2_direct', 'r3_invite'];
const POOL_TYPES = ['inbox', 'user'];
const ESCALATION_ACTIONS = ['renotify', 'escalate'];
const HANDOFF_PICKUP_THRESHOLD_DEFAULT = 900;

const isLoading = ref(false);
const isSaving = ref(false);
const loadFailed = ref(false);
const pipelines = ref([]);
const pipelineInboxes = ref([]);
const stages = ref([]);

const defaultHandoff = reactive({
  enabled: false,
  mode: 'round_robin',
  handoff_mode: 'r2_direct',
  trigger: '',
  prefer_online: true,
  pickup_threshold_seconds: HANDOFF_PICKUP_THRESHOLD_DEFAULT,
  escalation_user_id: null,
  pool_type: 'inbox',
  pool_id: null,
  escalation_action: 'renotify',
});

const stageForms = reactive({});

const pipelineId = computed(() => Number(route.params.pipelineId));
const currentPipeline = computed(() =>
  pipelines.value.find(pipeline => pipeline.id === pipelineId.value)
);
const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);

const breadcrumbItems = computed(() => [
  {
    label: t('CRM_KANBAN.HANDOFF_SETTINGS.INDEX_TITLE'),
    routeName: 'crm_handoff_settings_index',
  },
  { label: currentPipeline.value?.name || '' },
]);

const normalizePositiveSeconds = value => {
  const seconds = Number(value);
  return seconds > 0 ? Math.round(seconds) : HANDOFF_PICKUP_THRESHOLD_DEFAULT;
};

const normalizeUserId = value => {
  const userId = Number(value);
  return Number.isInteger(userId) && userId > 0 ? userId : null;
};

const toFormEntry = handoff => ({
  enabled: handoff?.enabled === true,
  mode: SELECTOR_MODES.includes(handoff?.mode) ? handoff.mode : 'round_robin',
  handoff_mode: FLOW_MODES.includes(handoff?.handoff_mode)
    ? handoff.handoff_mode
    : 'r2_direct',
  trigger: handoff?.trigger || '',
  prefer_online: handoff?.prefer_online !== false,
  pickup_threshold_seconds: normalizePositiveSeconds(
    handoff?.pickup_threshold_seconds
  ),
  escalation_user_id: normalizeUserId(handoff?.escalation_user_id),
  pool_type: POOL_TYPES.includes(handoff?.pool_type)
    ? handoff.pool_type
    : 'inbox',
  pool_id: normalizeUserId(handoff?.pool_id),
  escalation_action: ESCALATION_ACTIONS.includes(handoff?.escalation_action)
    ? handoff.escalation_action
    : 'renotify',
});

const loadSettings = async () => {
  if (!pipelineId.value) return;
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const [settingsResponse, pipelinesResponse, inboxesResponse] =
      await Promise.all([
        CrmKanbanAPI.getAiSettings(pipelineId.value),
        CrmKanbanAPI.getPipelines(),
        CrmKanbanAPI.getPipelineInboxes(pipelineId.value),
      ]);
    pipelines.value = pipelinesResponse.data.payload || [];
    pipelineInboxes.value = inboxesResponse.data.payload || [];

    const payload = settingsResponse.data.payload || {};
    Object.assign(defaultHandoff, toFormEntry(payload.handoff));

    stages.value = payload.stages || [];
    Object.keys(stageForms).forEach(key => delete stageForms[key]);
    stages.value.forEach(stage => {
      stageForms[stage.id] = {
        custom: stage.handoff_custom === true,
        ...toFormEntry(stage.handoff),
      };
    });
  } catch {
    loadFailed.value = true;
    useAlert(t('CRM_KANBAN.HANDOFF_SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const stageHandoffPayload = form =>
  form.custom
    ? {
        custom: true,
        enabled: form.enabled,
        mode: form.mode,
        handoff_mode: form.handoff_mode,
        trigger: form.trigger,
        prefer_online: form.prefer_online,
        pickup_threshold_seconds: form.pickup_threshold_seconds,
        escalation_user_id: form.escalation_user_id,
        pool_type: form.pool_type,
        pool_id: form.pool_id,
        escalation_action: form.escalation_action,
      }
    : { custom: false };

const saveSettings = async () => {
  if (!pipelineId.value) return;
  isSaving.value = true;
  try {
    const stageHandoff = Object.fromEntries(
      Object.entries(stageForms).map(([stageId, form]) => [
        stageId,
        stageHandoffPayload(form),
      ])
    );
    await CrmKanbanAPI.updateAiSettings(pipelineId.value, {
      ai_settings: { handoff: { ...defaultHandoff } },
      stage_handoff: stageHandoff,
    });
    useAlert(t('CRM_KANBAN.HANDOFF_SETTINGS.SAVE_SUCCESS'));
  } catch {
    useAlert(t('CRM_KANBAN.HANDOFF_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const pipelineChoices = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);

const switchPipeline = value => {
  const id = Number(value);
  if (!id || id === pipelineId.value) return;
  router.push({
    name: 'crm_handoff_settings_edit',
    params: { pipelineId: id },
  });
};

const handleBreadcrumbClick = item => {
  if (item.routeName) router.push({ name: item.routeName });
};

watch(
  pipelineId,
  () => {
    store.dispatch('agents/get');
    loadSettings();
  },
  { immediate: true }
);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :no-records-found="false"
    class="!gap-0"
  >
    <template #header>
      <header
        class="flex w-full items-start justify-between gap-4 bg-n-blue-12 px-6 py-5 sm:px-8"
      >
        <div class="min-w-0">
          <div class="flex min-w-0 items-center gap-2">
            <Button
              icon="i-lucide-arrow-left"
              slate
              ghost
              :aria-label="t('CRM_KANBAN.HANDOFF_SETTINGS.BACK_TO_CRM')"
              class="!h-11 !w-11 !text-n-slate-1"
              @click="router.push({ name: 'crm_kanban_index' })"
            />
            <Breadcrumb
              :items="breadcrumbItems"
              class="[&_*]:!text-n-slate-4 [&_button:hover]:!text-n-slate-1"
              @click="handleBreadcrumbClick"
            />
          </div>
          <h1 class="mb-1 mt-4 text-2xl font-semibold text-n-slate-1">
            {{ t('CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS') }}
          </h1>
          <p class="mb-0 truncate text-sm leading-6 text-n-slate-4">
            {{
              currentPipeline?.name ||
              t('CRM_KANBAN.HANDOFF_SETTINGS.INDEX_TITLE')
            }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          :aria-label="t('CRM_KANBAN.ACTIONS.CLOSE')"
          class="!h-11 !w-11 !text-n-slate-1"
          @click="router.push({ name: 'crm_handoff_settings_index' })"
        />
      </header>
    </template>

    <template #body>
      <div v-if="loadFailed" class="px-6 py-6 sm:px-8">
        <p
          role="alert"
          class="mb-0 rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
        >
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.LOAD_ERROR') }}
        </p>
      </div>

      <div v-else class="min-h-0 bg-n-surface-1">
        <div class="mx-auto grid w-full max-w-3xl gap-6 px-6 py-6 sm:px-8">
          <section
            class="grid gap-4 rounded-xl border border-solid border-n-weak bg-n-surface-1 p-4 sm:p-5"
          >
            <div
              class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between"
            >
              <div class="min-w-0">
                <p
                  class="mb-1 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('CRM_KANBAN.FILTERS.PIPELINE') }}
                </p>
                <h2 class="mb-0 text-lg font-semibold text-n-slate-12">
                  {{
                    currentPipeline?.name ||
                    t('CRM_KANBAN.HANDOFF_SETTINGS.INDEX_TITLE')
                  }}
                </h2>
              </div>
              <ChoiceSelect
                :model-value="pipelineId"
                :options="pipelineChoices"
                :aria-label="t('CRM_KANBAN.FILTERS.PIPELINE')"
                class="w-full sm:w-64 [&>button]:!bg-n-surface-1 [&>button]:!h-11"
                @change="switchPipeline"
              />
            </div>

            <div v-if="pipelineInboxes.length" class="grid gap-2">
              <span class="text-xs font-medium text-n-slate-11">
                {{ t('CRM_KANBAN.HANDOFF_SETTINGS.LINKED_INBOXES') }}
              </span>
              <div class="flex flex-wrap gap-2">
                <span
                  v-for="pipelineInbox in pipelineInboxes"
                  :key="pipelineInbox.id"
                  class="rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs text-n-slate-12"
                >
                  {{ pipelineInbox.inbox?.name || pipelineInbox.name }}
                </span>
              </div>
            </div>

            <p
              v-if="pipelineInboxes.length"
              class="mb-0 text-sm leading-6 text-n-slate-11"
            >
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.POOL_SOURCE_NOTE') }}
            </p>
          </section>

          <section
            class="grid gap-4 rounded-xl border border-solid border-n-weak bg-n-surface-1 p-4 sm:p-5"
          >
            <div>
              <h2 class="mb-1 text-lg font-semibold text-n-slate-12">
                {{ t('CRM_KANBAN.HANDOFF_SETTINGS.DEFAULT_TITLE') }}
              </h2>
              <p class="mb-0 text-sm leading-6 text-n-slate-11">
                {{ t('CRM_KANBAN.HANDOFF_SETTINGS.DEFAULT_HELP') }}
              </p>
            </div>
            <HandoffRuleFields
              v-model="defaultHandoff"
              :agent-options="agentOptions"
            />
          </section>

          <section class="grid gap-3">
            <div>
              <h2 class="mb-1 text-lg font-semibold text-n-slate-12">
                {{ t('CRM_KANBAN.HANDOFF_SETTINGS.STAGES_TITLE') }}
              </h2>
            </div>

            <details
              v-for="stage in stages"
              :key="`${pipelineId}-${stage.id}`"
              class="group rounded-xl border border-solid border-n-weak bg-n-surface-1"
            >
              <summary
                class="flex min-h-16 cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand sm:px-5 [&::-webkit-details-marker]:hidden"
              >
                <span class="min-w-0">
                  <strong
                    class="block truncate text-base font-semibold text-n-slate-12"
                  >
                    {{ stage.name }}
                  </strong>
                  <span class="mt-1 block text-sm text-n-slate-11">
                    {{
                      stageForms[stage.id]?.custom
                        ? t('CRM_KANBAN.HANDOFF_SETTINGS.USE_CUSTOM')
                        : t('CRM_KANBAN.HANDOFF_SETTINGS.INHERITS_DEFAULT')
                    }}
                  </span>
                </span>
                <span class="flex shrink-0 items-center gap-2">
                  <span
                    class="hidden rounded-full border px-2.5 py-1 text-xs font-medium sm:inline-flex"
                    :class="
                      stageForms[stage.id]?.custom
                        ? 'border-n-blue-4 bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak bg-n-surface-1 text-n-slate-11'
                    "
                  >
                    {{
                      stageForms[stage.id]?.custom
                        ? t('CRM_KANBAN.HANDOFF_SETTINGS.USE_CUSTOM')
                        : t('CRM_KANBAN.HANDOFF_SETTINGS.USE_DEFAULT')
                    }}
                  </span>
                  <span
                    class="i-lucide-chevron-down size-5 text-n-slate-10 transition-transform group-open:rotate-180"
                    aria-hidden="true"
                  />
                </span>
              </summary>

              <div class="grid gap-4 border-t border-n-weak p-4 sm:p-5">
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    class="min-h-11 rounded-lg border border-solid bg-n-surface-1 px-3 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      !stageForms[stage.id]?.custom
                        ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12'
                    "
                    :aria-pressed="!stageForms[stage.id]?.custom"
                    @click="stageForms[stage.id].custom = false"
                  >
                    {{ t('CRM_KANBAN.HANDOFF_SETTINGS.USE_DEFAULT') }}
                  </button>
                  <button
                    type="button"
                    class="min-h-11 rounded-lg border border-solid bg-n-surface-1 px-3 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    :class="
                      stageForms[stage.id]?.custom
                        ? 'border-n-brand bg-n-blue-2 text-n-blue-11'
                        : 'border-n-weak text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12'
                    "
                    :aria-pressed="stageForms[stage.id]?.custom"
                    @click="stageForms[stage.id].custom = true"
                  >
                    {{ t('CRM_KANBAN.HANDOFF_SETTINGS.USE_CUSTOM') }}
                  </button>
                </div>

                <p
                  v-if="!stageForms[stage.id]?.custom"
                  class="mb-0 text-sm leading-6 text-n-slate-11"
                >
                  {{ t('CRM_KANBAN.HANDOFF_SETTINGS.INHERITS_DEFAULT') }}
                </p>

                <HandoffRuleFields
                  v-else
                  v-model="stageForms[stage.id]"
                  :agent-options="agentOptions"
                />
              </div>
            </details>
          </section>
        </div>

        <footer
          class="sticky bottom-0 flex flex-wrap items-center justify-end gap-3 border-t border-n-weak bg-n-surface-1 px-6 py-4 sm:px-8"
        >
          <Button
            :label="t('CRM_KANBAN.HANDOFF_SETTINGS.CANCEL')"
            outline
            slate
            class="!min-h-11 !rounded-lg !bg-n-surface-1 !outline-n-weak"
            @click="router.push({ name: 'crm_handoff_settings_index' })"
          />
          <Button
            :label="t('CRM_KANBAN.HANDOFF_SETTINGS.SAVE')"
            icon="i-lucide-check"
            :is-loading="isSaving"
            :disabled="isLoading || loadFailed"
            class="!min-h-11 !rounded-lg"
            @click="saveSettings"
          />
        </footer>
      </div>
    </template>
  </SettingsLayout>
</template>
