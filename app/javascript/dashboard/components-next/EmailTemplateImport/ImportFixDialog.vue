<script setup>
// The small window that solves one warning of an imported model (#1099): the image that did not
// come, the part that became an image, or the field that does not exist here. Every choice is done
// on the server (EmailCampaigns::Import::Fixer); this only says which one.
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { FIELD_CHOICES, fieldLabelKey, tagOf } from './importRows';
import { MAX_IMAGE_BYTES } from './importErrors';

const props = defineProps({
  problem: { type: Object, default: null },
  isBusy: { type: Boolean, default: false },
  errorText: { type: String, default: '' },
});

const emit = defineEmits(['fix', 'close', 'restart']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN';
const dialog = useTemplateRef('dialog');
const imageInput = useTemplateRef('imageInput');
const choice = ref('');
const text = ref('');
const localError = ref('');

const TEXT = '__text__';
const REMOVE = '__remove__';

const fieldGroups = computed(() => [
  {
    label: t(`${S}.FIELD_DIALOG.GROUP_FIELDS`),
    options: FIELD_CHOICES.map(key => ({
      value: key,
      label: t(fieldLabelKey(key)),
    })),
  },
  {
    label: t(`${S}.FIELD_DIALOG.GROUP_OTHER`),
    options: [
      { value: TEXT, label: t(`${S}.FIELD_DIALOG.TEXT_OPTION`) },
      { value: REMOVE, label: t(`${S}.FIELD_DIALOG.REMOVE_OPTION`) },
    ],
  },
]);

const title = computed(() => {
  const type = props.problem?.type;
  if (type === 'image') {
    return t(
      `${S}.IMAGE_DIALOG.${props.problem.kind === 'background' ? 'BACKGROUND_TITLE' : 'TITLE'}`
    );
  }
  if (type === 'part') return t(`${S}.PART_DIALOG.TITLE`);
  if (type === 'field') {
    return t(`${S}.FIELD_DIALOG.TITLE`, {
      field: props.problem.label || tagOf(props.problem.target),
    });
  }
  return t(`${S}.ROWS.INVALID`);
});

const shownError = computed(() => localError.value || props.errorText);

const open = async () => {
  choice.value = '';
  text.value = '';
  localError.value = '';
  await nextTick();
  dialog.value?.open();
};

const close = () => dialog.value?.close();

watch(
  () => props.problem,
  value => {
    if (value) open();
  }
);

defineExpose({ open, close });

const send = payload =>
  emit('fix', {
    kind: props.problem.type,
    target: props.problem.target,
    ...payload,
  });

const pickImage = event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;
  if (file.size > MAX_IMAGE_BYTES) {
    localError.value = t('EMAIL_IMPORT.ERRORS.IMAGE_TOO_LARGE');
    return;
  }
  localError.value = '';
  send({ choice: 'upload', file });
};

const chooseField = () => {
  if (!choice.value) return;
  if (choice.value === TEXT) {
    if (!text.value.trim()) {
      localError.value = t('EMAIL_IMPORT.ERRORS.TEXT_INVALID');
      return;
    }
    send({ choice: 'text', value: text.value.trim() });
    return;
  }
  if (choice.value === REMOVE) send({ choice: 'remove' });
  else send({ choice: 'field', value: choice.value });
};
</script>

<template>
  <Dialog
    ref="dialog"
    :title="title"
    width="md"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="emit('close')"
  >
    <template v-if="problem?.type === 'image'">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t(`${S}.IMAGE_DIALOG.TEXT`) }}
      </p>
      <input
        ref="imageInput"
        type="file"
        accept="image/png,image/jpeg,image/gif,image/webp"
        class="hidden"
        @change="pickImage"
      />
      <div class="flex flex-col gap-2">
        <Button
          type="button"
          :label="t(`${S}.IMAGE_DIALOG.UPLOAD`)"
          icon="i-lucide-upload"
          size="lg"
          class="!min-h-12 w-full !rounded-xl"
          :is-loading="isBusy"
          @click="imageInput.click()"
        />
        <p class="mb-1 text-center text-xs text-n-slate-11">
          {{ t(`${S}.IMAGE_DIALOG.UPLOAD_HINT`) }}
        </p>
        <Button
          type="button"
          :label="t(`${S}.IMAGE_DIALOG.REMOVE`)"
          icon="i-lucide-trash-2"
          slate
          outline
          class="!min-h-11 w-full !rounded-xl"
          :disabled="isBusy"
          @click="send({ choice: 'remove' })"
        />
      </div>
    </template>

    <template v-else-if="problem?.type === 'part'">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t(`${S}.PART_DIALOG.TEXT`) }}
      </p>
      <blockquote
        v-if="problem.text"
        class="m-0 max-h-32 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
      >
        {{ problem.text }}
      </blockquote>
      <div class="flex flex-col gap-2">
        <Button
          type="button"
          :label="t(`${S}.PART_DIALOG.REBUILD`)"
          icon="i-lucide-sparkles"
          size="lg"
          class="!min-h-12 w-full !rounded-xl"
          disabled
          :title="t(`${S}.PART_DIALOG.SOON`)"
        />
        <p class="mb-1 text-center text-xs text-n-slate-11">
          {{ t(`${S}.PART_DIALOG.SOON`) }}
        </p>
        <Button
          v-if="problem.text"
          type="button"
          :label="t(`${S}.PART_DIALOG.KEEP_TEXT`)"
          icon="i-lucide-type"
          slate
          outline
          class="!min-h-11 w-full !rounded-xl"
          :is-loading="isBusy"
          @click="send({ choice: 'text' })"
        />
        <Button
          type="button"
          :label="t(`${S}.PART_DIALOG.REMOVE`)"
          icon="i-lucide-trash-2"
          slate
          outline
          class="!min-h-11 w-full !rounded-xl"
          :disabled="isBusy"
          @click="send({ choice: 'remove' })"
        />
      </div>
    </template>

    <template v-else-if="problem?.type === 'field'">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t(`${S}.FIELD_DIALOG.TEXT`) }}
      </p>
      <ChoiceSelect
        v-model="choice"
        :groups="fieldGroups"
        :aria-label="title"
        :placeholder="t(`${S}.FIELD_DIALOG.PLACEHOLDER`)"
        class="w-full"
      />
      <label v-if="choice === TEXT" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${S}.FIELD_DIALOG.TEXT_LABEL`) }}
        </span>
        <input
          v-model="text"
          type="text"
          maxlength="200"
          class="m-0 min-h-12 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 text-base text-n-slate-12"
        />
        <span class="text-xs text-n-slate-11">{{
          t(`${S}.FIELD_DIALOG.TEXT_HINT`)
        }}</span>
      </label>
      <Button
        type="button"
        :label="t(`${S}.FIELD_DIALOG.${choice === TEXT ? 'DONE' : 'CHOOSE'}`)"
        size="lg"
        class="!min-h-12 w-full !rounded-xl"
        :disabled="!choice"
        :is-loading="isBusy"
        @click="chooseField"
      />
    </template>

    <template v-else-if="problem">
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t(`${S}.ROWS.INVALID_HINT`) }}
      </p>
      <Button
        type="button"
        :label="t(`${S}.RESULT.ANOTHER`)"
        size="lg"
        class="!min-h-12 w-full !rounded-xl"
        @click="emit('restart')"
      />
    </template>

    <p
      v-if="shownError"
      class="mb-0 text-sm font-medium text-n-ruby-11"
      role="alert"
    >
      {{ shownError }}
    </p>

    <template #footer>
      <Button
        type="button"
        :label="t(`${S}.LATER`)"
        ghost
        slate
        class="!min-h-11 w-full !rounded-xl"
        @click="close"
      />
    </template>
  </Dialog>
</template>
