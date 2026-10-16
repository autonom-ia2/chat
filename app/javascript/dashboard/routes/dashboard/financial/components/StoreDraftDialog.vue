<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import StoreAPI from 'dashboard/api/autonomia/store';

const props = defineProps({
  target: { type: Object, required: true },
});
const emit = defineEmits(['created']);
const { t } = useI18n();
const dialog = useTemplateRef('dialog');
const name = ref('');
const description = ref('');
const intent = ref('');
const loading = ref(false);
const error = ref('');
const valid = computed(
  () =>
    name.value.trim().length >= 2 &&
    name.value.trim().length <= 160 &&
    description.value.length <= 2000
);
const open = initialName => {
  name.value = initialName;
  description.value = '';
  intent.value = crypto.randomUUID();
  error.value = '';
  dialog.value.open();
};
const create = async () => {
  if (!valid.value || loading.value) return;
  loading.value = true;
  error.value = '';
  try {
    const response = await StoreAPI.createService(props.target, {
      name: name.value.trim(),
      description: description.value.trim() || null,
      idempotencyKey: intent.value,
    });
    emit('created', response.data.service);
    dialog.value?.close();
  } catch {
    error.value = t('FINANCIAL.STORE.PUBLICATION.ERROR');
  } finally {
    loading.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('FINANCIAL.STORE.PUBLICATION.CREATE')"
    :confirm-button-label="t('FINANCIAL.STORE.PUBLICATION.SUBMIT')"
    :cancel-button-label="t('FINANCIAL.STORE.CLOSE')"
    :disable-confirm-button="!valid || loading"
    :is-loading="loading"
    :show-cancel-button="!loading"
    width="lg"
    class="break-words"
    overflow-y-auto
    @confirm="create"
  >
    <div class="flex flex-col min-w-0 max-h-[55dvh] gap-4 overflow-y-auto">
      <label class="flex flex-col gap-2 text-sm text-n-slate-12">
        {{ t('FINANCIAL.STORE.PUBLICATION.NAME') }}
        <input
          v-model="name"
          type="text"
          required
          minlength="2"
          maxlength="160"
          :disabled="loading"
          class="w-full min-w-0 px-3 py-2 border rounded-lg border-n-weak bg-n-solid-2"
        />
      </label>
      <label class="flex flex-col gap-2 text-sm text-n-slate-12">
        {{ t('FINANCIAL.STORE.PUBLICATION.DESCRIPTION') }}
        <textarea
          v-model="description"
          maxlength="2000"
          rows="4"
          :disabled="loading"
          class="w-full min-w-0 px-3 py-2 border rounded-lg resize-y border-n-weak bg-n-solid-2"
        />
      </label>
      <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </div>
  </Dialog>
</template>
