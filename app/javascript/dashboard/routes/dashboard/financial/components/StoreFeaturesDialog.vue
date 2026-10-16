<script setup>
import { computed, onBeforeUnmount, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import StorePublicationPanel from './StorePublicationPanel.vue';
import { useStoreLabels } from '../composables/useStoreLabels';

const { t } = useI18n();
const labels = useStoreLabels();
const dialog = useTemplateRef('dialog');
const features = ref([]);
const selected = ref('');
const loading = ref(false);
const error = ref('');
const target = computed(() => ({ featureKey: selected.value }));
const featureLabel = key => labels.value.features[key];
const options = computed(() =>
  features.value.map(key => ({ value: key, label: featureLabel(key) }))
);
let request;
const load = async () => {
  request?.abort();
  const controller = new AbortController();
  request = controller;
  features.value = [];
  selected.value = '';
  loading.value = true;
  error.value = '';
  try {
    const response = await StoreAPI.features(controller.signal);
    if (request !== controller || controller.signal.aborted) return;
    features.value = response.data.data;
    selected.value = features.value[0] || '';
  } catch {
    if (!controller.signal.aborted)
      error.value = t('FINANCIAL.STORE.PUBLICATION.LOAD_ERROR');
  } finally {
    if (request === controller) loading.value = false;
  }
};
const open = () => {
  dialog.value.open();
  load();
};
const close = () => {
  request?.abort();
  features.value = [];
  selected.value = '';
};
onBeforeUnmount(close);
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('FINANCIAL.STORE.MANAGE_FEATURES')"
    :show-confirm-button="false"
    :cancel-button-label="t('FINANCIAL.STORE.CLOSE')"
    width="xl"
    class="break-words"
    overflow-y-auto
    @close="close"
  >
    <div class="flex flex-col min-w-0 max-h-[60dvh] gap-5 overflow-y-auto">
      <Spinner v-if="loading" />
      <div v-else-if="error" class="space-y-3">
        <p role="alert" class="m-0 text-sm text-n-ruby-11">{{ error }}</p>
        <Button
          :label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          @click="load"
        />
      </div>
      <template v-else-if="selected">
        <ChoiceSelect
          v-model="selected"
          :options="options"
          :aria-label="t('FINANCIAL.STORE.GROUPS.FEATURE')"
          class="w-full min-w-0"
        />
        <StorePublicationPanel
          :key="selected"
          :target="target"
          :default-name="featureLabel(selected)"
        />
      </template>
    </div>
  </Dialog>
</template>
