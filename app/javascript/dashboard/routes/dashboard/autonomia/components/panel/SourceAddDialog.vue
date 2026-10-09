<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['added', 'close']);

const { t } = useI18n();
const store = useStore();

const ACCEPTED_FORMATS = '.pdf,.txt,.md,.json,.xlsx,.docx';

const dialogRef = ref(null);
const mode = ref('link');
const linkUrl = ref('');
const selectedFile = ref(null);
const fileInputRef = ref(null);
const isSubmitting = ref(false);

const isLinkMode = computed(() => mode.value === 'link');

const canSubmit = computed(() => {
  if (isLinkMode.value) return Boolean(linkUrl.value.trim());
  return Boolean(selectedFile.value);
});

const open = () => {
  mode.value = 'link';
  linkUrl.value = '';
  selectedFile.value = null;
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const onFileChange = event => {
  selectedFile.value = event.target.files?.[0] || null;
};

const triggerFilePicker = () => {
  fileInputRef.value?.click();
};

const onConfirm = async () => {
  if (!canSubmit.value || isSubmitting.value) return;

  const descriptor = isLinkMode.value
    ? { url: linkUrl.value.trim(), kind: 'knowledge' }
    : { file: selectedFile.value };

  try {
    isSubmitting.value = true;
    await store.dispatch('autonomiaSources/create', {
      agentId: props.agentId,
      descriptor,
    });
    useAlert(t('AGENTS.KNOWLEDGE.ADD_SUCCESS'));
    emit('added');
    close();
  } catch (error) {
    useAlert(t('AGENTS.KNOWLEDGE.ADD_ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AGENTS.KNOWLEDGE.ADD')"
    :confirm-button-label="t('AGENTS.KNOWLEDGE.ADD')"
    :disable-confirm-button="!canSubmit"
    :is-loading="isSubmitting"
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <div class="flex gap-2 p-1 rounded-lg bg-n-alpha-1 w-fit">
        <button
          type="button"
          :aria-pressed="isLinkMode"
          class="px-3 py-1.5 text-sm rounded-md transition-colors"
          :class="
            isLinkMode
              ? 'bg-n-solid-active text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="mode = 'link'"
        >
          {{ t('AGENTS.KNOWLEDGE.ADD_LINK') }}
        </button>
        <button
          type="button"
          :aria-pressed="!isLinkMode"
          class="px-3 py-1.5 text-sm rounded-md transition-colors"
          :class="
            !isLinkMode
              ? 'bg-n-solid-active text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="mode = 'file'"
        >
          {{ t('AGENTS.KNOWLEDGE.ADD_FILE') }}
        </button>
      </div>

      <Input
        v-if="isLinkMode"
        v-model="linkUrl"
        type="url"
        :label="t('AGENTS.KNOWLEDGE.LINK_LABEL')"
        :placeholder="t('AGENTS.KNOWLEDGE.LINK_PLACEHOLDER')"
      />

      <div v-else class="flex flex-col gap-2">
        <input
          ref="fileInputRef"
          type="file"
          class="hidden"
          :accept="ACCEPTED_FORMATS"
          @change="onFileChange"
        />
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-2 px-4 py-6 transition-colors border border-dashed rounded-lg border-n-weak hover:border-n-brand text-n-slate-11"
          @click="triggerFilePicker"
        >
          <Icon icon="i-lucide-upload" class="text-xl" />
          <span v-if="selectedFile" class="text-sm text-n-slate-12">
            {{ selectedFile.name }}
          </span>
          <span v-else class="text-sm">
            {{ t('AGENTS.KNOWLEDGE.FILE_PLACEHOLDER') }}
          </span>
        </button>
      </div>

      <p class="text-xs text-n-slate-11">
        {{ t('AGENTS.KNOWLEDGE.FORMATS_HINT') }}
      </p>
    </div>
  </Dialog>
</template>
