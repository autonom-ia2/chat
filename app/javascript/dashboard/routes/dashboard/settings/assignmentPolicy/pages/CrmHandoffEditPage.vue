<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import Button from 'dashboard/components-next/button/Button.vue';
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

const switchPipeline = event => {
  const id = Number(event.target.value);
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
  <SettingsLayout :is-loading="isLoading" :no-records-found="false">
    <template #header>
      <div class="flex min-h-10 w-full items-center gap-2">
        <Button
          icon="i-lucide-arrow-left"
          slate
          ghost
          sm
          :aria-label="t('CRM_KANBAN.HANDOFF_SETTINGS.BACK_TO_CRM')"
          @click="router.push({ name: 'crm_kanban_index' })"
        />
        <Breadcrumb :items="breadcrumbItems" @click="handleBreadcrumbClick" />
      </div>
    </template>

    <template #body>
      <p v-if="loadFailed" class="mb-0 pt-4 text-sm text-n-ruby-11">
        {{ t('CRM_KANBAN.HANDOFF_SETTINGS.LOAD_ERROR') }}
      </p>

      <div v-else class="grid max-w-3xl gap-5 pt-4">
        <div class="flex flex-wrap items-center gap-3">
          <select
            :value="pipelineId"
            class="reset-base max-w-64 rounded-lg border-0 bg-n-surface-2 px-3 py-2 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-strong"
            @change="switchPipeline"
          >
            <option
              v-for="pipeline in pipelines"
              :key="pipeline.id"
              :value="pipeline.id"
            >
              {{ pipeline.name }}
            </option>
          </select>
          <div
            v-if="pipelineInboxes.length"
            class="flex flex-wrap items-center gap-1.5"
          >
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.LINKED_INBOXES') }}
            </span>
            <span
              v-for="pipelineInbox in pipelineInboxes"
              :key="pipelineInbox.id"
              class="rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs text-n-slate-12"
            >
              {{ pipelineInbox.inbox?.name || pipelineInbox.name }}
            </span>
          </div>
        </div>

        <p class="mb-0 text-xs leading-5 text-n-slate-10">
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.POOL_SOURCE_NOTE') }}
        </p>

        <section
          class="grid gap-4 rounded-xl bg-n-alpha-black2 p-4 outline outline-1 outline-n-weak"
        >
          <div>
            <h3 class="mb-1 text-sm font-medium text-n-slate-12">
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.DEFAULT_TITLE') }}
            </h3>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.DEFAULT_HELP') }}
            </p>
          </div>
          <HandoffRuleFields
            v-model="defaultHandoff"
            :agent-options="agentOptions"
          />
        </section>

        <section class="grid gap-3">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.HANDOFF_SETTINGS.STAGES_TITLE') }}
          </h3>

          <div
            v-for="stage in stages"
            :key="stage.id"
            class="grid gap-3 rounded-xl bg-n-alpha-black2 p-4 outline outline-1 outline-n-weak"
          >
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm font-medium text-n-slate-12">
                {{ stage.name }}
              </span>
              <div
                class="flex shrink-0 items-center gap-1 rounded-lg bg-n-alpha-2 p-0.5"
              >
                <button
                  type="button"
                  class="rounded-md px-2.5 py-1 text-xs"
                  :class="
                    !stageForms[stage.id]?.custom
                      ? 'bg-n-solid-3 text-n-slate-12'
                      : 'text-n-slate-11'
                  "
                  @click="stageForms[stage.id].custom = false"
                >
                  {{ t('CRM_KANBAN.HANDOFF_SETTINGS.USE_DEFAULT') }}
                </button>
                <button
                  type="button"
                  class="rounded-md px-2.5 py-1 text-xs"
                  :class="
                    stageForms[stage.id]?.custom
                      ? 'bg-n-solid-3 text-n-slate-12'
                      : 'text-n-slate-11'
                  "
                  @click="stageForms[stage.id].custom = true"
                >
                  {{ t('CRM_KANBAN.HANDOFF_SETTINGS.USE_CUSTOM') }}
                </button>
              </div>
            </div>

            <p
              v-if="!stageForms[stage.id]?.custom"
              class="mb-0 text-xs leading-5 text-n-slate-11"
            >
              {{ t('CRM_KANBAN.HANDOFF_SETTINGS.INHERITS_DEFAULT') }}
            </p>

            <HandoffRuleFields
              v-else
              v-model="stageForms[stage.id]"
              :agent-options="agentOptions"
            />
          </div>
        </section>

        <div class="flex items-center justify-end gap-2 pb-6">
          <Button
            :label="t('CRM_KANBAN.HANDOFF_SETTINGS.CANCEL')"
            slate
            faded
            @click="router.push({ name: 'crm_handoff_settings_index' })"
          />
          <Button
            :label="t('CRM_KANBAN.HANDOFF_SETTINGS.SAVE')"
            icon="i-lucide-check"
            :is-loading="isSaving"
            :disabled="isLoading || loadFailed"
            @click="saveSettings"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
