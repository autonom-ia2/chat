<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import AgentSwitch from '../AgentSwitch.vue';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import ToolDialog from './ToolDialog.vue';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const tools = ref([]);
const isLoading = ref(false);
const loadError = ref(false);
const isDialogOpen = ref(false);
const editingTool = ref(null);
const isSaving = ref(false);
const testingId = ref(null);
const testResult = ref(null);
const testingTool = ref(null);
const testValues = reactive({});
const deleteTarget = ref(null);
const deleteDialog = ref(null);
const testDialog = ref(null);
const { run } = useAbortableRequest();

const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');
const canUseTools = computed(
  () =>
    isSuperAdmin.value &&
    props.canManage &&
    props.agent.agent_type !== 'insurance_quote'
);

const loadTools = async () => {
  if (!isSuperAdmin.value || props.agent.agent_type === 'insurance_quote')
    return;
  isLoading.value = true;
  loadError.value = false;
  try {
    const response = await run(signal =>
      AutonomiaAgentsAPI.getTools(props.agentId, { signal })
    );
    if (!response) return;
    tools.value = response.data.payload;
  } catch (error) {
    if (isAbortError(error)) return;
    loadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const openNew = () => {
  editingTool.value = null;
  isDialogOpen.value = true;
};

const openEdit = tool => {
  editingTool.value = tool;
  isDialogOpen.value = true;
};

const closeDialog = () => {
  isDialogOpen.value = false;
  editingTool.value = null;
};

const saveTool = async tool => {
  if (!canUseTools.value || isSaving.value) return;
  isSaving.value = true;
  try {
    if (editingTool.value) {
      await AutonomiaAgentsAPI.updateTool(
        props.agentId,
        editingTool.value.id,
        tool
      );
    } else {
      await AutonomiaAgentsAPI.createTool(props.agentId, tool);
    }
    closeDialog();
    await loadTools();
    useAlert(t('AGENTS.PANEL.REDESIGN_TOOLS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_TOOLS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const toggleTool = async (tool, enabled) => {
  if (!canUseTools.value || tool.enabled === enabled) return;
  try {
    await AutonomiaAgentsAPI.updateTool(props.agentId, tool.id, { enabled });
    tool.enabled = enabled;
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_TOOLS.SAVE_ERROR'));
  }
};

const testTool = async (tool, params = {}) => {
  if (!canUseTools.value || testingId.value) return;
  testingId.value = tool.id;
  testResult.value = null;
  try {
    const response = await AutonomiaAgentsAPI.testTool(
      props.agentId,
      tool.id,
      params
    );
    const data = response?.data || response || {};
    testResult.value = {
      toolId: tool.id,
      status: data.status || 'ok',
      body: data.body || data.error || '',
    };
  } catch (error) {
    testResult.value = {
      toolId: tool.id,
      status: 'error',
      body: error?.message || t('AGENTS.PANEL.REDESIGN_TOOLS.TEST_ERROR'),
    };
  } finally {
    testingId.value = null;
  }
};

const clearTestValues = () => {
  Object.keys(testValues).forEach(key => delete testValues[key]);
};

const openTest = tool => {
  const params = (tool.param_schema || []).filter(param => param.name);
  if (!params.length) {
    testTool(tool, {});
    return;
  }

  testingTool.value = tool;
  clearTestValues();
  params.forEach(param => {
    testValues[param.name] = '';
  });
  testDialog.value?.open();
};

const closeTest = () => {
  testingTool.value = null;
  clearTestValues();
};

const testParams = tool =>
  Object.fromEntries(
    (tool.param_schema || [])
      .filter(param => param.name)
      .map(param => {
        const value = testValues[param.name] ?? '';
        if (param.type === 'number' && value !== '')
          return [param.name, Number(value)];
        if (param.type === 'integer' && value !== '') {
          return [param.name, Number.parseInt(value, 10)];
        }
        if (param.type === 'boolean' && value !== '') {
          return [param.name, value === 'true'];
        }
        return [param.name, value];
      })
  );

const runToolTest = async () => {
  const tool = testingTool.value;
  if (!tool) return;
  const requiredParam = (tool.param_schema || []).find(
    param =>
      param.required !== false && !String(testValues[param.name] || '').trim()
  );
  if (requiredParam) {
    useAlert(
      t('AGENTS.PANEL.REDESIGN_TOOLS.TEST_REQUIRED', {
        name: requiredParam.name,
      })
    );
    return;
  }

  const params = testParams(tool);
  testDialog.value?.close();
  await testTool(tool, params);
};

const openDelete = tool => {
  if (!canUseTools.value) return;
  deleteTarget.value = tool;
  deleteDialog.value?.open();
};

const closeDelete = () => {
  deleteTarget.value = null;
};

const deleteTool = async () => {
  const tool = deleteTarget.value;
  deleteDialog.value?.close();
  deleteTarget.value = null;
  if (!tool || !canUseTools.value) return;
  try {
    await AutonomiaAgentsAPI.deleteTool(props.agentId, tool.id);
    await loadTools();
    useAlert(t('AGENTS.PANEL.REDESIGN_TOOLS.DELETED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_TOOLS.DELETE_ERROR'));
  }
};

onMounted(loadTools);
</script>

<template>
  <section
    data-test="panel-tools-v2"
    class="flex flex-col w-full max-w-4xl gap-6 px-6 py-6 mx-auto"
  >
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('AGENTS.PANEL.REDESIGN_TOOLS.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS.PANEL.REDESIGN_TOOLS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        class="!bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
        v-if="canUseTools"
        solid
        sm
        :label="t('AGENTS.PANEL.REDESIGN_TOOLS.NEW')"
        :disabled="tools.length >= 10"
        data-test="new-tool"
        @click="openNew"
      />
    </header>

    <div
      v-if="!isSuperAdmin"
      class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl bg-n-amber-9/10 text-n-amber-12"
      data-test="tools-access"
    >
      <i class="flex-shrink-0 mt-0.5 i-lucide-lock-keyhole size-4" />
      <span>{{ t('AGENTS.PANEL.REDESIGN_TOOLS.ACCESS') }}</span>
    </div>
    <div
      v-else-if="props.agent.agent_type === 'insurance_quote'"
      class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl bg-n-iris-2 text-n-iris-11"
      data-test="tools-quote-hidden"
    >
      <i class="flex-shrink-0 mt-0.5 i-lucide-info size-4" />
      <span>{{ t('AGENTS.PANEL.REDESIGN_TOOLS.QUOTE_HIDDEN') }}</span>
    </div>

    <p v-if="isLoading" class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.PANEL.REDESIGN_TOOLS.LOADING') }}
    </p>
    <div v-else-if="loadError" class="flex flex-col gap-3" role="alert">
      <p class="m-0 text-sm text-n-ruby-11">
        {{ t('AGENTS.PANEL.REDESIGN_TOOLS.LOAD_ERROR') }}
      </p>
      <Button
        outline
        sm
        :label="t('AGENTS.PANEL.REDESIGN_TOOLS.RETRY')"
        @click="loadTools"
      />
    </div>
    <p
      v-else-if="isSuperAdmin && !tools.length"
      class="p-5 m-0 text-sm border rounded-xl border-n-weak text-n-slate-11"
      data-test="tools-empty"
    >
      {{ t('AGENTS.PANEL.REDESIGN_TOOLS.EMPTY') }}
    </p>
    <div v-else class="flex flex-col gap-3">
      <article
        v-for="tool in tools"
        :key="tool.id"
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="m-0 text-base font-semibold text-n-slate-12">
                {{ tool.name }}
              </h2>
              <span
                class="px-2 py-1 text-xs rounded-full"
                :class="
                  tool.enabled
                    ? 'bg-n-teal-9/15 text-n-teal-12'
                    : 'bg-n-slate-9/15 text-n-slate-11'
                "
              >
                {{
                  t(
                    tool.enabled
                      ? 'AGENTS.PANEL.REDESIGN_TOOLS.ENABLED'
                      : 'AGENTS.PANEL.REDESIGN_TOOLS.DISABLED'
                  )
                }}
              </span>
            </div>
            <p class="mt-1 mb-0 text-xs text-n-slate-11">
              {{
                t('AGENTS.PANEL.REDESIGN_TOOLS.SLUG_METHOD', {
                  slug: tool.slug,
                  method: tool.http_method,
                })
              }}
            </p>
            <p class="mt-2 mb-0 text-sm text-n-slate-11">
              {{ tool.description }}
            </p>
          </div>
          <div class="flex items-center gap-3">
            <span class="flex items-center gap-2 text-xs text-n-slate-11">
              <AgentSwitch
                :checked="tool.enabled"
                :disabled="!canUseTools"
                :label="
                  t('AGENTS.PANEL.REDESIGN_TOOLS.TOGGLE_LABEL', {
                    name: tool.name,
                  })
                "
                :aria-label="
                  t('AGENTS.PANEL.REDESIGN_TOOLS.TOGGLE_LABEL', {
                    name: tool.name,
                  })
                "
                @toggle="toggleTool(tool, $event)"
              />
            </span>
            <button
              type="button"
              class="flex items-center justify-center min-w-11 min-h-11 rounded-xl text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-label="t('AGENTS.PANEL.REDESIGN_TOOLS.TEST')"
              :title="t('AGENTS.PANEL.REDESIGN_TOOLS.TEST')"
              :disabled="!canUseTools || testingId === tool.id"
              :data-test="`tool-test-${tool.id}`"
              @click="openTest(tool)"
            >
              <i class="i-lucide-play size-4" />
            </button>
            <button
              type="button"
              class="flex items-center justify-center min-w-11 min-h-11 rounded-xl text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-label="t('AGENTS.PANEL.REDESIGN_TOOLS.EDIT')"
              :title="t('AGENTS.PANEL.REDESIGN_TOOLS.EDIT')"
              :disabled="!canUseTools"
              :data-test="`tool-edit-${tool.id}`"
              @click="openEdit(tool)"
            >
              <i class="i-lucide-pencil size-4" />
            </button>
            <button
              type="button"
              class="flex items-center justify-center min-w-11 min-h-11 rounded-xl text-n-ruby-10 hover:bg-n-ruby-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-label="t('AGENTS.PANEL.REDESIGN_TOOLS.DELETE')"
              :title="t('AGENTS.PANEL.REDESIGN_TOOLS.DELETE')"
              :disabled="!canUseTools"
              :data-test="`tool-delete-${tool.id}`"
              @click="openDelete(tool)"
            >
              <i class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>

        <pre
          v-if="testResult?.toolId === tool.id"
          class="p-4 m-0 overflow-auto text-xs whitespace-pre-wrap border rounded-xl border-n-weak bg-n-alpha-1 text-n-slate-11"
          data-test="tool-result"
          >{{ `${testResult.status}\n${testResult.body}` }}</pre
        >
      </article>
    </div>

    <p
      v-if="isSuperAdmin && tools.length >= 10"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t('AGENTS.PANEL.REDESIGN_TOOLS.LIMIT') }}
    </p>
    <p v-if="isSuperAdmin && !tools.length" class="m-0 text-sm text-n-slate-11">
      {{ t('AGENTS.PANEL.REDESIGN_TOOLS.STOCK_HINT') }}
    </p>
  </section>

  <ToolDialog
    :is-open="isDialogOpen"
    :tool="editingTool"
    :is-saving="isSaving"
    @save="saveTool"
    @close="closeDialog"
  />

  <Dialog
    ref="deleteDialog"
    type="alert"
    :title="t('AGENTS.PANEL.REDESIGN_TOOLS.DELETE_TITLE')"
    :description="
      t('AGENTS.PANEL.REDESIGN_TOOLS.DELETE_DESCRIPTION', {
        name: deleteTarget?.name,
      })
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="closeDelete"
  >
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl border border-n-strong text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="delete-cancel"
          @click="deleteDialog.close()"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL') }}
        </button>
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl font-semibold bg-n-ruby-11 text-white dark:text-n-navy hover:bg-n-ruby-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="delete-confirm"
          @click="deleteTool"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CONFIRM') }}
        </button>
      </div>
    </template>
  </Dialog>

  <Dialog
    ref="testDialog"
    :title="t('AGENTS.PANEL.REDESIGN_TOOLS.TEST_TITLE')"
    :description="t('AGENTS.PANEL.REDESIGN_TOOLS.TEST_DESCRIPTION')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="closeTest"
  >
    <div v-if="testingTool" class="flex flex-col gap-4">
      <Input
        v-for="param in testingTool.param_schema || []"
        :key="param.name"
        v-model="testValues[param.name]"
        :label="param.name"
        :type="['number', 'integer'].includes(param.type) ? 'number' : 'text'"
        :placeholder="param.description || param.type"
        :disabled="!!testingId"
        :data-test="`test-param-${param.name}`"
      />
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl border border-n-strong text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="test-cancel"
          @click="testDialog.close()"
        >
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL') }}
        </button>
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl font-semibold bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-test="test-run"
          :disabled="!!testingId"
          @click="runToolTest"
        >
          {{ t('AGENTS.PANEL.REDESIGN_TOOLS.TEST') }}
        </button>
      </div>
    </template>
  </Dialog>
</template>
