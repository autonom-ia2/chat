<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();

const tools = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const editingId = ref(null);
const testResult = ref('');

const emptyForm = () => ({
  name: '',
  slug: '',
  description: '',
  enabled: true,
  http_method: 'POST',
  endpoint_url: '',
  request_body_template: '{ "q": "{{q}}", "limit": 5 }',
  headers_config: [
    { key: 'content-type', value: 'application/json', secret: false },
    { key: 'x-api-key', value: '', secret: true },
  ],
  param_schema: [
    {
      name: 'q',
      type: 'string',
      description: 'Termo principal da busca informado pelo cliente',
      required: true,
    },
  ],
  response_mapping: {},
});

const form = reactive(emptyForm());

const isEditing = computed(() => editingId.value !== null);

const resetForm = () => {
  Object.assign(form, emptyForm());
  editingId.value = null;
  testResult.value = '';
};

const applyStockTemplate = () => {
  Object.assign(form, emptyForm(), {
    name: 'Consulta de estoque',
    slug: 'consultar_estoque',
    description:
      'Consulta produtos disponíveis no estoque por termo de busca. Use quando o cliente perguntar por peça, aplicação, produto ou disponibilidade.',
    endpoint_url:
      'https://giraautopecas.api-autonomia.com/clients/gira-autopecas/stock/search',
  });
};

const loadTools = async () => {
  isLoading.value = true;
  try {
    const { data } = await AutonomiaAgentsAPI.getTools(props.agentId);
    tools.value = data.payload || [];
  } finally {
    isLoading.value = false;
  }
};

const editTool = tool => {
  editingId.value = tool.id;
  Object.assign(form, {
    name: tool.name || '',
    slug: tool.slug || '',
    description: tool.description || '',
    enabled: tool.enabled !== false,
    http_method: tool.http_method || 'POST',
    endpoint_url: tool.endpoint_url || '',
    request_body_template: tool.request_body_template || '',
    headers_config: tool.headers_config?.length
      ? tool.headers_config.map(header => ({ ...header }))
      : [],
    param_schema: tool.param_schema?.length
      ? tool.param_schema.map(param => ({ ...param }))
      : [],
    response_mapping: tool.response_mapping || {},
  });
  testResult.value = '';
};

const addHeader = () => {
  form.headers_config.push({ key: '', value: '', secret: false });
};

const removeHeader = index => {
  form.headers_config.splice(index, 1);
};

const addParam = () => {
  form.param_schema.push({
    name: '',
    type: 'string',
    description: '',
    required: true,
  });
};

const removeParam = index => {
  form.param_schema.splice(index, 1);
};

const payload = () => ({
  name: form.name,
  slug: form.slug,
  description: form.description,
  enabled: form.enabled,
  http_method: form.http_method,
  endpoint_url: form.endpoint_url,
  request_body_template: form.request_body_template,
  headers_config: form.headers_config,
  param_schema: form.param_schema,
  response_mapping: form.response_mapping,
});

const saveTool = async () => {
  isSaving.value = true;
  try {
    if (isEditing.value) {
      await AutonomiaAgentsAPI.updateTool(props.agentId, editingId.value, payload());
    } else {
      await AutonomiaAgentsAPI.createTool(props.agentId, payload());
    }
    useAlert(t('AGENTS.TOOLS.SAVE_SUCCESS'));
    resetForm();
    await loadTools();
  } catch (error) {
    useAlert(error?.message || t('AGENTS.TOOLS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const deleteTool = async tool => {
  if (!window.confirm(t('AGENTS.TOOLS.DELETE_CONFIRM'))) return;
  await AutonomiaAgentsAPI.deleteTool(props.agentId, tool.id);
  useAlert(t('AGENTS.TOOLS.DELETE_SUCCESS'));
  await loadTools();
};

const testTool = async tool => {
  testResult.value = '';
  try {
    const params = Object.fromEntries(
      (tool.param_schema || []).map(param => [
        param.name,
        param.name === 'q' ? 'freio dianteiro titan' : '',
      ])
    );
    const { data } = await AutonomiaAgentsAPI.testTool(
      props.agentId,
      tool.id,
      params
    );
    testResult.value = data.body || '';
    useAlert(t('AGENTS.TOOLS.TEST_SUCCESS'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.TOOLS.TEST_ERROR'));
  }
};

onMounted(loadTools);
</script>

<template>
  <section class="max-w-6xl p-6 mx-auto space-y-6">
    <div class="flex items-start justify-between gap-4">
      <div>
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('AGENTS.TOOLS.TITLE') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('AGENTS.TOOLS.DESCRIPTION') }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:brightness-110"
        @click="applyStockTemplate"
      >
        <i class="i-lucide-package-search size-4" />
        {{ t('AGENTS.TOOLS.STOCK_TEMPLATE') }}
      </button>
    </div>

    <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_420px]">
      <div class="space-y-3">
        <div
          v-if="isLoading"
          class="p-4 text-sm border rounded-lg border-n-weak text-n-slate-11"
        >
          {{ t('AGENTS.TOOLS.LOADING') }}
        </div>
        <div
          v-else-if="!tools.length"
          class="p-4 text-sm border rounded-lg border-n-weak text-n-slate-11"
        >
          {{ t('AGENTS.TOOLS.EMPTY') }}
        </div>
        <article
          v-for="tool in tools"
          :key="tool.id"
          class="p-4 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <h3 class="font-medium truncate text-n-slate-12">
                  {{ tool.name }}
                </h3>
                <span
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="
                    tool.enabled
                      ? 'bg-n-teal-9/15 text-n-teal-11'
                      : 'bg-n-slate-9/15 text-n-slate-11'
                  "
                >
                  {{
                    tool.enabled
                      ? t('AGENTS.TOOLS.ENABLED')
                      : t('AGENTS.TOOLS.DISABLED')
                  }}
                </span>
              </div>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ tool.slug }} · {{ tool.http_method }}
              </p>
              <p class="mt-2 text-sm text-n-slate-11">
                {{ tool.description }}
              </p>
            </div>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="p-2 rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                @click="testTool(tool)"
              >
                <i class="i-lucide-play size-4" />
              </button>
              <button
                type="button"
                class="p-2 rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                @click="editTool(tool)"
              >
                <i class="i-lucide-pencil size-4" />
              </button>
              <button
                type="button"
                class="p-2 rounded-md text-n-ruby-10 hover:bg-n-ruby-3"
                @click="deleteTool(tool)"
              >
                <i class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>
        </article>
        <pre
          v-if="testResult"
          class="p-3 overflow-auto text-xs border rounded-lg max-h-52 border-n-weak bg-n-alpha-1 text-n-slate-11"
        >{{ testResult }}</pre>
      </div>

      <form
        class="p-4 space-y-4 border rounded-lg border-n-weak bg-n-solid-1"
        @submit.prevent="saveTool"
      >
        <div class="flex items-center justify-between gap-3">
          <h3 class="font-medium text-n-slate-12">
            {{
              isEditing
                ? t('AGENTS.TOOLS.EDIT_TITLE')
                : t('AGENTS.TOOLS.CREATE_TITLE')
            }}
          </h3>
          <button
            v-if="isEditing"
            type="button"
            class="text-sm text-n-brand"
            @click="resetForm"
          >
            {{ t('AGENTS.TOOLS.NEW') }}
          </button>
        </div>

        <label class="block space-y-1 text-sm">
          <span class="text-n-slate-11">{{ t('AGENTS.TOOLS.NAME') }}</span>
          <input
            v-model="form.name"
            class="w-full min-h-10 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
            required
          />
        </label>
        <label class="block space-y-1 text-sm">
          <span class="text-n-slate-11">{{ t('AGENTS.TOOLS.SLUG') }}</span>
          <input
            v-model="form.slug"
            class="w-full min-h-10 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
            required
          />
        </label>
        <label class="block space-y-1 text-sm">
          <span class="text-n-slate-11">{{
            t('AGENTS.TOOLS.DESCRIPTION_LABEL')
          }}</span>
          <textarea
            v-model="form.description"
            rows="3"
            class="w-full px-3 py-2 text-sm border rounded-lg outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
            required
          />
        </label>
        <div class="grid grid-cols-[110px_1fr] gap-3">
          <label class="block space-y-1 text-sm">
            <span class="text-n-slate-11">{{ t('AGENTS.TOOLS.METHOD') }}</span>
            <select v-model="form.http_method" class="w-full min-h-10 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand">
              <option>GET</option>
              <option>POST</option>
            </select>
          </label>
          <label class="block space-y-1 text-sm">
            <span class="text-n-slate-11">{{ t('AGENTS.TOOLS.URL') }}</span>
            <input
              v-model="form.endpoint_url"
              class="w-full min-h-10 px-3 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
              required
            />
          </label>
        </div>
        <label class="block space-y-1 text-sm">
          <span class="text-n-slate-11">{{ t('AGENTS.TOOLS.BODY') }}</span>
          <textarea
            v-model="form.request_body_template"
            rows="4"
            class="w-full px-3 py-2 font-mono text-xs border rounded-lg outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
          />
        </label>

        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-sm text-n-slate-11">{{
              t('AGENTS.TOOLS.HEADERS')
            }}</span>
            <button type="button" class="text-sm text-n-brand" @click="addHeader">
              {{ t('AGENTS.TOOLS.ADD') }}
            </button>
          </div>
          <div
            v-for="(header, index) in form.headers_config"
            :key="`header-${index}`"
            class="grid grid-cols-[1fr_1fr_auto_auto] gap-2"
          >
            <input
              v-model="header.key"
              class="min-h-9 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
              placeholder="x-api-key"
            />
            <input
              v-model="header.value"
              class="min-h-9 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
              placeholder="valor"
            />
            <label class="inline-flex items-center gap-1 text-xs text-n-slate-11">
              <input v-model="header.secret" type="checkbox" />
              {{ t('AGENTS.TOOLS.SECRET') }}
            </label>
            <button
              type="button"
              class="p-2 text-n-slate-10"
              @click="removeHeader(index)"
            >
              <i class="i-lucide-x size-4" />
            </button>
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-sm text-n-slate-11">{{
              t('AGENTS.TOOLS.PARAMS')
            }}</span>
            <button type="button" class="text-sm text-n-brand" @click="addParam">
              {{ t('AGENTS.TOOLS.ADD') }}
            </button>
          </div>
          <div
            v-for="(param, index) in form.param_schema"
            :key="`param-${index}`"
            class="grid grid-cols-[1fr_100px_auto_auto] gap-2"
          >
            <input
              v-model="param.name"
              class="min-h-9 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
              placeholder="q"
            />
            <select v-model="param.type" class="min-h-9 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand">
              <option>string</option>
              <option>number</option>
              <option>integer</option>
              <option>boolean</option>
            </select>
            <label class="inline-flex items-center gap-1 text-xs text-n-slate-11">
              <input v-model="param.required" type="checkbox" />
              {{ t('AGENTS.TOOLS.REQUIRED') }}
            </label>
            <button
              type="button"
              class="p-2 text-n-slate-10"
              @click="removeParam(index)"
            >
              <i class="i-lucide-x size-4" />
            </button>
            <input
              v-model="param.description"
              class="col-span-4 min-h-9 px-2 text-sm border rounded-lg outline-none border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand"
              :placeholder="t('AGENTS.TOOLS.PARAM_DESCRIPTION')"
            />
          </div>
        </div>

        <label class="inline-flex items-center gap-2 text-sm text-n-slate-11">
          <input v-model="form.enabled" type="checkbox" />
          {{ t('AGENTS.TOOLS.ACTIVE') }}
        </label>

        <button
          type="submit"
          :disabled="isSaving"
          class="inline-flex items-center justify-center w-full gap-2 px-3 py-2 text-sm font-medium text-white rounded-lg bg-n-brand hover:brightness-110 disabled:opacity-50"
        >
          <i class="i-lucide-save size-4" />
          {{ t('AGENTS.TOOLS.SAVE') }}
        </button>
      </form>
    </div>
  </section>
</template>
