<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agentId: { type: Number, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['added', 'close']);
const MAX_FILE_BYTES = 25 * 1024 * 1024;
const ACCEPTED_EXTENSIONS = ['pdf', 'docx', 'xlsx', 'txt', 'md', 'json'];
const ACCEPTED_FORMATS = '.pdf,.docx,.xlsx,.txt,.md,.json';

const { t } = useI18n();

const dialogRef = ref(null);
const fileInputRef = ref(null);
const mode = ref('link');
const linkUrl = ref('');
const selectedFile = ref(null);
const validationError = ref('');
const hasRequestError = ref(false);
const isSubmitting = ref(false);

const isLinkMode = computed(() => mode.value === 'link');

watch(linkUrl, () => {
  validationError.value = '';
  hasRequestError.value = false;
});

const isValidUrl = value => {
  try {
    const url = new URL(value.trim());
    return ['http:', 'https:'].includes(url.protocol) && Boolean(url.hostname);
  } catch {
    return false;
  }
};

const extensionFor = file => {
  const name = file?.name || '';
  const separator = name.lastIndexOf('.');
  return separator === -1 ? '' : name.slice(separator + 1).toLowerCase();
};

const canSubmit = computed(() => {
  if (props.disabled || isSubmitting.value || validationError.value)
    return false;
  if (isLinkMode.value) return Boolean(linkUrl.value.trim());
  return Boolean(selectedFile.value);
});

const reset = () => {
  mode.value = 'link';
  linkUrl.value = '';
  selectedFile.value = null;
  validationError.value = '';
  hasRequestError.value = false;
  isSubmitting.value = false;
};

const open = () => {
  if (props.disabled) return;
  reset();
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const selectMode = nextMode => {
  mode.value = nextMode;
  validationError.value = '';
  hasRequestError.value = false;
  if (nextMode === 'link') selectedFile.value = null;
  else linkUrl.value = '';
};

const onFileChange = event => {
  const file = event.target.files?.[0] || null;
  selectedFile.value = null;
  validationError.value = '';
  hasRequestError.value = false;
  if (!file) return;

  if (!ACCEPTED_EXTENSIONS.includes(extensionFor(file))) {
    validationError.value = 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_TYPE_ERROR';
    return;
  }
  if (file.size > MAX_FILE_BYTES) {
    validationError.value = 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_SIZE_ERROR';
    return;
  }
  selectedFile.value = file;
};

const submit = async () => {
  if (props.disabled || isSubmitting.value) return;
  if (isLinkMode.value && !isValidUrl(linkUrl.value)) {
    validationError.value = 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.URL_ERROR';
    return;
  }
  if (!canSubmit.value) return;

  hasRequestError.value = false;
  isSubmitting.value = true;
  const descriptor = isLinkMode.value
    ? { url: linkUrl.value.trim(), kind: 'knowledge' }
    : { file: selectedFile.value, kind: 'knowledge' };

  try {
    await AutonomiaSourcesAPI.create(props.agentId, descriptor);
    emit('added');
    close();
  } catch {
    hasRequestError.value = true;
  } finally {
    isSubmitting.value = false;
  }
};

const handleClose = () => emit('close');

const validationMessage = computed(() => {
  if (validationError.value === 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.URL_ERROR') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.URL_ERROR');
  }
  if (
    validationError.value === 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_TYPE_ERROR'
  ) {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_TYPE_ERROR');
  }
  if (
    validationError.value === 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_SIZE_ERROR'
  ) {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_SIZE_ERROR');
  }
  return '';
});

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD_TITLE')"
    width="sm"
    @confirm="submit"
    @close="handleClose"
  >
    <div class="flex flex-col min-w-0 gap-4" data-testid="add-material-dialog">
      <div class="flex gap-2 p-1 rounded-lg bg-n-alpha-1" role="group">
        <Button
          ghost
          slate
          type="button"
          size="sm"
          class="min-h-11 grow"
          :class="{ 'bg-n-solid-active text-n-slate-12 shadow-sm': isLinkMode }"
          :aria-pressed="isLinkMode"
          :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD_LINK')"
          data-action="mode-link"
          @click="selectMode('link')"
        />
        <Button
          ghost
          slate
          type="button"
          size="sm"
          class="min-h-11 grow"
          :class="{
            'bg-n-solid-active text-n-slate-12 shadow-sm': !isLinkMode,
          }"
          :aria-pressed="!isLinkMode"
          :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD_FILE')"
          data-action="mode-file"
          @click="selectMode('file')"
        />
      </div>

      <Input
        v-if="isLinkMode"
        v-model="linkUrl"
        type="url"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.LINK_LABEL')"
        :placeholder="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.LINK_PLACEHOLDER')"
        :message="validationMessage"
        message-type="error"
      />
      <p v-if="isLinkMode && validationMessage" class="sr-only" role="alert">
        {{ validationMessage }}
      </p>

      <div v-if="!isLinkMode" class="flex flex-col min-w-0 gap-2">
        <input
          ref="fileInputRef"
          type="file"
          class="hidden"
          :accept="ACCEPTED_FORMATS"
          :aria-label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_LABEL')"
          @change="onFileChange"
        />
        <Button
          outline
          slate
          type="button"
          size="lg"
          justify="start"
          icon="i-lucide-upload"
          class="min-h-11 w-full !h-auto py-5"
          :label="
            selectedFile?.name ||
            t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FILE_PLACEHOLDER')
          "
          data-action="choose-file"
          @click="fileInputRef?.click()"
        />
        <p
          v-if="validationMessage"
          class="m-0 text-xs text-n-ruby-11"
          role="alert"
        >
          {{ validationMessage }}
        </p>
      </div>

      <p class="m-0 text-xs leading-5 text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FORMATS') }}
      </p>
      <p v-if="!isLinkMode" class="m-0 text-xs leading-5 text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.WORD_EXCEL_NOTICE') }}
      </p>
      <p v-if="hasRequestError" class="m-0 text-sm text-n-ruby-11" role="alert">
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD_ERROR') }}
      </p>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          faded
          color="slate"
          type="button"
          class="w-full"
          :label="t('DIALOG.BUTTONS.CANCEL')"
          :disabled="isSubmitting"
          data-action="cancel"
          @click="close"
        />
        <Button
          solid
          type="submit"
          class="w-full !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
          :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD')"
          :is-loading="isSubmitting"
          :disabled="!canSubmit"
          data-action="confirm"
        />
      </div>
    </template>
  </Dialog>
</template>
