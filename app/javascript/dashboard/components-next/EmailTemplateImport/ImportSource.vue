<script setup>
import { computed, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ImportStepDots from './ImportStepDots.vue';
import { sizeLabel } from './importErrors';

const props = defineProps({
  mode: {
    type: String,
    required: true,
    validator: value => ['paste', 'file', 'url'].includes(value),
  },
  initialFile: { type: Object, default: null },
  // What the person sent last time, back on the screen after a problem with it (the address that did not open).
  initialInput: { type: Object, default: null },
  errorText: { type: String, default: '' },
  isSending: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'back']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN';
const sameMode = props.initialInput?.kind === props.mode;
const content = ref(sameMode ? props.initialInput.content || '' : '');
const address = ref(sameMode ? props.initialInput.url || '' : '');
const file = ref(
  props.initialFile || (sameMode ? props.initialInput.file : null)
);
const isDragging = ref(false);
const fileInput = useTemplateRef('fileInput');

watch(
  () => props.initialFile,
  value => {
    if (value) file.value = value;
  }
);

const pastedSize = computed(() => new Blob([content.value]).size);
const canSend = computed(() => {
  if (props.mode === 'paste') return content.value.trim().length > 0;
  if (props.mode === 'url') return address.value.trim().length > 0;
  return Boolean(file.value);
});

const pickFile = event => {
  const [picked] = event.target.files || [];
  if (picked) file.value = picked;
  event.target.value = '';
};

const onDrop = event => {
  isDragging.value = false;
  const [dropped] = event.dataTransfer?.files || [];
  if (dropped) file.value = dropped;
};

const submit = () => {
  if (!canSend.value || props.isSending) return;
  if (props.mode === 'paste')
    emit('submit', { kind: 'paste', content: content.value });
  else if (props.mode === 'url')
    emit('submit', { kind: 'url', url: address.value.trim() });
  else emit('submit', { kind: 'file', file: file.value });
};
</script>

<template>
  <form class="mx-auto w-full max-w-[55rem]" @submit.prevent="submit">
    <div class="mb-4 flex items-center justify-between gap-3">
      <ImportStepDots :current="1" />
      <Button
        type="button"
        :label="t(`${S}.BACK`)"
        icon="i-lucide-arrow-left"
        ghost
        class="!min-h-11"
        @click="emit('back')"
      />
    </div>
    <h1
      class="mb-2 text-2xl font-semibold tracking-tight text-n-slate-12 sm:text-[1.75rem]"
    >
      {{ t(`${S}.${mode.toUpperCase()}.TITLE`) }}
    </h1>
    <p class="mb-5 text-base text-n-slate-11">
      {{ t(`${S}.${mode.toUpperCase()}.LEAD`) }}
    </p>

    <label v-if="mode === 'paste'" class="block">
      <span class="sr-only">{{ t(`${S}.PASTE.LABEL`) }}</span>
      <textarea
        v-model="content"
        rows="12"
        spellcheck="false"
        autocomplete="off"
        class="m-0 block min-h-72 w-full resize-y rounded-2xl border border-n-weak bg-n-solid-1 p-4 font-mono text-xs leading-5 text-n-slate-12 focus:border-n-brand"
        :aria-invalid="Boolean(errorText)"
      />
    </label>

    <div v-else-if="mode === 'url'">
      <label
        class="mb-2 block text-sm font-medium text-n-slate-12"
        for="import-url"
      >
        {{ t(`${S}.URL.LABEL`) }}
      </label>
      <input
        id="import-url"
        v-model="address"
        type="url"
        inputmode="url"
        autocomplete="off"
        :placeholder="t(`${S}.URL.PLACEHOLDER`)"
        class="m-0 min-h-12 w-full rounded-xl border border-n-weak bg-n-solid-1 px-4 text-base text-n-slate-12 focus:border-n-brand"
        :aria-invalid="Boolean(errorText)"
      />
    </div>

    <div v-else>
      <input
        ref="fileInput"
        type="file"
        accept=".html,.htm,.zip,text/html,application/zip"
        class="hidden"
        @change="pickFile"
      />
      <button
        type="button"
        class="flex min-h-44 w-full flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed p-6 text-center transition-colors"
        :class="
          isDragging
            ? 'border-n-brand bg-n-blue-2'
            : 'border-n-strong bg-n-solid-1'
        "
        @click="fileInput.click()"
        @dragover.prevent="isDragging = true"
        @dragleave="isDragging = false"
        @drop.prevent="onDrop"
      >
        <template v-if="file">
          <span class="i-lucide-file-check size-8 text-n-teal-11" />
          <b class="break-all text-base text-n-slate-12">{{ file.name }}</b>
          <span class="text-sm text-n-slate-11">{{
            sizeLabel(file.size)
          }}</span>
          <span class="text-sm font-semibold text-n-blue-11">
            {{ t(`${S}.FILE.CHANGE`) }}
          </span>
        </template>
        <template v-else>
          <span class="i-lucide-upload size-8 text-n-blue-11" />
          <b class="text-base text-n-slate-12">{{ t(`${S}.FILE.DROP`) }}</b>
          <span class="text-sm text-n-slate-11">{{
            t(`${S}.FILE.DROP_HINT`)
          }}</span>
        </template>
      </button>
    </div>

    <p
      v-if="errorText"
      class="mb-0 mt-3 text-sm font-medium text-n-ruby-11"
      role="alert"
    >
      {{ errorText }}
    </p>

    <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
      <span
        v-if="mode === 'paste' && content.trim()"
        class="flex items-center gap-1.5 text-sm text-n-slate-11"
      >
        <span class="i-lucide-check size-4 text-n-teal-11" />
        {{ t(`${S}.PASTE.RECEIVED`, { size: sizeLabel(pastedSize) }) }}
      </span>
      <span v-else />
      <Button
        type="submit"
        :label="t(`${S}.${mode.toUpperCase()}.GO`)"
        icon="i-lucide-arrow-right"
        trailing-icon
        size="lg"
        class="!min-h-12 !rounded-xl"
        :disabled="!canSend"
        :is-loading="isSending"
      />
    </div>
  </form>
</template>
