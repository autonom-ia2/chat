<script setup>
import { computed, onBeforeUnmount, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { canAccessStore } from 'dashboard/helper/storeAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import StoreDraftDialog from './StoreDraftDialog.vue';
import StorePublicationRow from './StorePublicationRow.vue';

const props = defineProps({
  target: { type: Object, required: true },
  defaultName: { type: String, default: '' },
});
const { t } = useI18n();
const user = useMapGetter('getCurrentUser');
const route = useRoute();
const allowed = computed(() => canAccessStore(user.value));
const services = ref([]);
const serviceId = ref('');
const serviceOptions = computed(() =>
  services.value.map(service => ({ value: service.id, label: service.name }))
);
const selectedService = computed(() =>
  services.value.find(service => service.id === serviceId.value)
);
const loading = ref(false);
const error = ref('');
const dialog = useTemplateRef('dialog');
let request;
const load = async () => {
  request?.abort();
  services.value = [];
  serviceId.value = '';
  error.value = '';
  if (!allowed.value) return;
  const controller = new AbortController();
  request = controller;
  loading.value = true;
  try {
    const response = await StoreAPI.services(props.target, controller.signal);
    if (request === controller && !controller.signal.aborted) {
      services.value = response.data.data;
      serviceId.value = services.value[0]?.id || '';
    }
  } catch (failure) {
    if (!controller.signal.aborted)
      error.value = t('FINANCIAL.STORE.PUBLICATION.LOAD_ERROR');
  } finally {
    if (request === controller) loading.value = false;
  }
};
watch([() => props.target, () => route.params.accountId, allowed], load, {
  immediate: true,
});
onBeforeUnmount(() => request?.abort());
</script>

<template>
  <section class="min-w-0 space-y-5">
    <template v-if="allowed">
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('FINANCIAL.STORE.PUBLICATION.TITLE') }}
        </h2>
        <Button
          :label="t('FINANCIAL.STORE.PUBLICATION.CREATE')"
          icon="i-lucide-plus"
          :disabled="loading"
          @click="dialog.open(defaultName)"
        />
      </header>
      <Spinner v-if="loading" />
      <div
        v-else-if="error"
        role="alert"
        class="flex flex-wrap items-center gap-2 text-sm text-n-ruby-11"
      >
        {{ error }}
        <Button
          :label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          @click="load"
        />
      </div>
      <p v-else-if="!services.length" class="text-sm text-n-slate-11">
        {{ t('FINANCIAL.STORE.PUBLICATION.EMPTY') }}
      </p>
      <template v-else>
        <ChoiceSelect
          v-model="serviceId"
          :options="serviceOptions"
          :aria-label="t('FINANCIAL.STORE.PUBLICATION_SERVICE')"
          class="w-full"
        />
        <StorePublicationRow
          v-if="selectedService"
          :key="selectedService.id"
          :target="target"
          :service="selectedService"
        />
      </template>
      <StoreDraftDialog ref="dialog" :target="target" @created="load" />
    </template>
  </section>
</template>
