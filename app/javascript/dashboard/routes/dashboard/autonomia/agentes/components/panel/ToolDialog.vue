<script setup>
import { onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  isOpen: { type: Boolean, default: false },
  tool: { type: Object, default: null },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();
const dialog = ref(null);

const MASKED_SECRET = '••••••••';
const METHOD_OPTIONS = [
  { value: 'GET', label: 'GET' },
  { value: 'POST', label: 'POST' },
];
const PARAM_OPTIONS = [
  { value: 'string', label: 'string' },
  { value: 'number', label: 'number' },
  { value: 'integer', label: 'integer' },
  { value: 'boolean', label: 'boolean' },
];

const emptyForm = () => ({
  name: '',
  slug: '',
  description: '',
  enabled: true,
  http_method: 'GET',
  endpoint_url: '',
  request_body_template: '',
  headers_config: [],
  param_schema: [],
  response_mapping: {},
});

const form = reactive(emptyForm());

const copyHeader = header => ({
  key: header.key || '',
  value: header.value || '',
  secret: header.secret === true,
});

const loadTool = tool => {
  Object.assign(form, emptyForm());
  if (!tool) return;
  Object.assign(form, {
    name: tool.name || '',
    slug: tool.slug || '',
    description: tool.description || '',
    enabled: tool.enabled !== false,
    http_method: tool.http_method || 'GET',
    endpoint_url: tool.endpoint_url || '',
    request_body_template: tool.request_body_template || '',
    headers_config: (tool.headers_config || []).map(copyHeader),
    param_schema: (tool.param_schema || []).map(param => ({
      name: param.name || '',
      type: param.type || 'string',
      description: param.description || '',
      required: param.required !== false,
    })),
    response_mapping: tool.response_mapping || {},
  });
};

watch(() => props.tool, loadTool, { immediate: true });

const open = () => {
  loadTool(props.tool);
  dialog.value?.open();
};
const close = () => dialog.value?.close();

watch(
  () => props.isOpen,
  openState => {
    if (openState) open();
    else close();
  },
  { immediate: true }
);

onMounted(() => {
  if (props.isOpen) open();
});

const applyStockTemplate = () => {
  Object.assign(form, {
    name: t('AGENTS.PANEL.REDESIGN_TOOLS.STOCK_NAME'),
    slug: 'consultar_estoque',
    description: t('AGENTS.PANEL.REDESIGN_TOOLS.STOCK_DESCRIPTION'),
    enabled: true,
    http_method: 'GET',
    endpoint_url: 'https://example.test/stock/search',
    request_body_template: '',
    headers_config: [],
    param_schema: [
      {
        name: 'q',
        type: 'string',
        description: t('AGENTS.PANEL.REDESIGN_TOOLS.STOCK_PARAM_DESCRIPTION'),
        required: true,
      },
    ],
    response_mapping: {},
  });
};

const addHeader = () => {
  form.headers_config.push({ key: '', value: '', secret: false });
};
const removeHeader = index => form.headers_config.splice(index, 1);
const addParam = () =>
  form.param_schema.push({
    name: '',
    type: 'string',
    description: '',
    required: true,
  });
const removeParam = index => form.param_schema.splice(index, 1);

const headersPayload = () =>
  form.headers_config.map(header => {
    if (header.secret && header.value === MASKED_SECRET) {
      return { key: header.key, secret: true };
    }
    return { ...header };
  });

const submit = () => {
  emit('save', {
    name: form.name.trim(),
    slug: form.slug.trim(),
    description: form.description.trim(),
    enabled: form.enabled,
    http_method: form.http_method,
    endpoint_url: form.endpoint_url.trim(),
    request_body_template: form.request_body_template,
    headers_config: headersPayload(),
    param_schema: form.param_schema.map(param => ({ ...param })),
    response_mapping: form.response_mapping,
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="
      tool
        ? t('AGENTS.PANEL.REDESIGN_TOOLS.EDIT_TITLE')
        : t('AGENTS.PANEL.REDESIGN_TOOLS.CREATE_TITLE')
    "
    width="2xl"
    overflow-y-auto
    :show-confirm-button="false"
    :show-cancel-button="false"
    @confirm="submit"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-5">
      <div class="grid gap-4 md:grid-cols-2">
        <Input
          v-model="form.name"
          :label="t('AGENTS.PANEL.REDESIGN_TOOLS.NAME')"
          :disabled="isSaving"
          data-test="tool-name"
        />
        <Input
          v-model="form.slug"
          :label="t('AGENTS.PANEL.REDESIGN_TOOLS.SLUG')"
          :disabled="isSaving"
          data-test="tool-slug"
        />
      </div>
      <TextArea
        v-model="form.description"
        id="tool-description"
        :label="t('AGENTS.PANEL.REDESIGN_TOOLS.WHEN')"
        :disabled="isSaving"
        data-test="tool-when"
      />

      <div class="grid gap-4 md:grid-cols-2">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_TOOLS.METHOD') }}
          </label>
          <ChoiceSelect
            v-model="form.http_method"
            :options="METHOD_OPTIONS"
            :aria-label="t('AGENTS.PANEL.REDESIGN_TOOLS.METHOD')"
            :disabled="isSaving"
            data-test="tool-method"
          />
        </div>
        <Input
          v-model="form.endpoint_url"
          :label="t('AGENTS.PANEL.REDESIGN_TOOLS.URL')"
          type="url"
          :disabled="isSaving"
          data-test="tool-url"
        />
      </div>

      <TextArea
        v-model="form.request_body_template"
        id="tool-request-body"
        :label="t('AGENTS.PANEL.REDESIGN_TOOLS.BODY')"
        :placeholder="t('AGENTS.PANEL.REDESIGN_TOOLS.BODY_PLACEHOLDER')"
        :disabled="isSaving"
        data-test="tool-body"
      />

      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_TOOLS.HEADERS') }}
          </h3>
          <Button
            outline
            sm
            type="button"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.ADD_HEADER')"
            :disabled="isSaving"
            data-test="add-header"
            @click="addHeader"
          />
        </div>
        <div
          v-for="(header, index) in form.headers_config"
          :key="index"
          class="grid items-end gap-2 md:grid-cols-[1fr_1fr_auto_auto]"
        >
          <Input
            v-model="header.key"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.HEADER_NAME')"
            :disabled="isSaving"
            :data-test="`header-key-${index}`"
          />
          <Input
            v-model="header.value"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.HEADER_VALUE')"
            :type="header.secret ? 'password' : 'text'"
            :disabled="isSaving"
            :data-test="`header-value-${index}`"
          />
          <label class="flex items-center h-10 gap-2 text-xs text-n-slate-11">
            <input
              v-model="header.secret"
              type="checkbox"
              :disabled="isSaving"
            />
            {{ t('AGENTS.PANEL.REDESIGN_TOOLS.SECRET') }}
          </label>
          <Button
            link
            sm
            color="ruby"
            class="!text-n-ruby-11 dark:!text-n-ruby-11"
            type="button"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.REMOVE')"
            :disabled="isSaving"
            @click="removeHeader(index)"
          />
        </div>
        <p
          v-if="!form.headers_config.length"
          class="m-0 text-xs text-n-slate-11"
        >
          {{ t('AGENTS.PANEL.REDESIGN_TOOLS.NO_HEADERS') }}
        </p>
      </div>

      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_TOOLS.PARAMETERS') }}
          </h3>
          <Button
            outline
            sm
            type="button"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.ADD_PARAMETER')"
            :disabled="isSaving"
            data-test="add-param"
            @click="addParam"
          />
        </div>
        <div
          v-for="(param, index) in form.param_schema"
          :key="index"
          class="grid gap-2 p-3 border rounded-xl border-n-weak md:grid-cols-[1fr_8rem_1fr_auto]"
        >
          <Input
            v-model="param.name"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.PARAMETER_NAME')"
            :disabled="isSaving"
            :data-test="`param-name-${index}`"
          />
          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-n-slate-12">
              {{ t('AGENTS.PANEL.REDESIGN_TOOLS.PARAMETER_TYPE') }}
            </label>
            <ChoiceSelect
              v-model="param.type"
              :options="PARAM_OPTIONS"
              :aria-label="t('AGENTS.PANEL.REDESIGN_TOOLS.PARAMETER_TYPE')"
              :disabled="isSaving"
              :data-test="`param-type-${index}`"
            />
          </div>
          <Input
            v-model="param.description"
            :label="t('AGENTS.PANEL.REDESIGN_TOOLS.PARAMETER_DESCRIPTION')"
            :disabled="isSaving"
            :data-test="`param-description-${index}`"
          />
          <div class="flex flex-col items-start gap-2">
            <label class="flex items-center gap-2 h-10 text-xs text-n-slate-11">
              <input
                v-model="param.required"
                type="checkbox"
                :disabled="isSaving"
              />
              {{ t('AGENTS.PANEL.REDESIGN_TOOLS.REQUIRED') }}
            </label>
            <Button
              link
              sm
              color="ruby"
              class="!text-n-ruby-11 dark:!text-n-ruby-11"
              type="button"
              :label="t('AGENTS.PANEL.REDESIGN_TOOLS.REMOVE')"
              :disabled="isSaving"
              @click="removeParam(index)"
            />
          </div>
        </div>
        <p v-if="!form.param_schema.length" class="m-0 text-xs text-n-slate-11">
          {{ t('AGENTS.PANEL.REDESIGN_TOOLS.NO_PARAMETERS') }}
        </p>
      </div>

      <label class="flex items-center gap-3 text-sm text-n-slate-12">
        <input v-model="form.enabled" type="checkbox" :disabled="isSaving" />
        {{ t('AGENTS.PANEL.REDESIGN_TOOLS.ENABLED') }}
      </label>
    </div>

    <template #footer>
      <div class="flex flex-wrap items-center justify-between w-full gap-3">
        <Button
          outline
          sm
          type="button"
          :label="t('AGENTS.PANEL.REDESIGN_TOOLS.STOCK_TEMPLATE')"
          :disabled="isSaving"
          data-test="stock-template"
          @click="applyStockTemplate"
        />
        <div class="flex gap-3">
          <Button
            faded
            color="slate"
            sm
            type="button"
            :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL')"
            :disabled="isSaving"
            data-test="tool-cancel"
            @click="close"
          />
          <Button
            class="!bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
            solid
            sm
            type="submit"
            :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
            :is-loading="isSaving"
            :disabled="isSaving"
            data-test="tool-save"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
