<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import StoreAPI from 'dashboard/api/autonomia/store';

const props = defineProps({
  target: { type: Object, required: true },
  service: { type: Object, required: true },
});
const { t } = useI18n();
const publication = ref(null);
const loading = ref(false);
const error = ref('');
const order = ref(0);
let request;
const load = async () => {
  request?.abort();
  const controller = new AbortController();
  request = controller;
  publication.value = null;
  error.value = '';
  loading.value = true;
  try {
    const response = await StoreAPI.publication(
      props.target,
      props.service.id,
      controller.signal
    );
    if (request !== controller) return;
    publication.value = response.data.publication;
    order.value = publication.value.displayOrder;
  } catch (failure) {
    if (!controller.signal.aborted && failure.response?.status !== 404)
      error.value = t('FINANCIAL.STORE.PUBLICATION.LOAD_ERROR');
  } finally {
    if (request === controller) loading.value = false;
  }
};
const publish = async () => {
  if (
    loading.value ||
    !Number.isInteger(order.value) ||
    order.value < 0 ||
    order.value > 1000000
  )
    return;
  loading.value = true;
  error.value = '';
  try {
    const response = await StoreAPI.publish(props.target, props.service.id, {
      status: publication.value?.status === 'active' ? 'inactive' : 'active',
      displayOrder: order.value,
    });
    publication.value = response.data.publication;
  } catch (failure) {
    error.value =
      failure.response?.status === 409
        ? t('FINANCIAL.STORE.PUBLICATION_INELIGIBLE')
        : t('FINANCIAL.STORE.PUBLICATION.ERROR');
  } finally {
    loading.value = false;
  }
};
watch([() => props.target, () => props.service.id], load, { immediate: true });
onBeforeUnmount(() => request?.abort());
</script>

<template>
  <div class="flex flex-col min-w-0 gap-3 py-4 border-b border-n-weak">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="min-w-0">
        <h3 class="m-0 text-sm font-medium break-words text-n-slate-12">
          {{ service.name }}
        </h3>
        <span class="text-xs text-n-slate-11">{{
          publication?.status === 'active'
            ? t('FINANCIAL.STORE.PUBLICATION.ACTIVE')
            : t('FINANCIAL.STORE.PUBLICATION.INACTIVE')
        }}</span>
      </div>
      <div class="flex flex-wrap items-end gap-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('FINANCIAL.STORE.PUBLICATION.ORDER') }}
          <input
            v-model.number="order"
            type="number"
            min="0"
            max="1000000"
            step="1"
            class="w-24 m-0"
            :disabled="loading"
          />
        </label>
        <Button
          :label="
            publication?.status === 'active'
              ? t('FINANCIAL.STORE.PUBLICATION.UNPUBLISH')
              : t('FINANCIAL.STORE.PUBLICATION.PUBLISH')
          "
          :icon="
            publication?.status === 'active'
              ? 'i-lucide-eye-off'
              : 'i-lucide-eye'
          "
          :disabled="
            Boolean(error) ||
            loading ||
            !Number.isInteger(order) ||
            order < 0 ||
            order > 1000000
          "
          :is-loading="loading"
          @click="publish"
        />
      </div>
    </div>
    <div v-if="error" class="flex flex-wrap items-center gap-2">
      <p role="alert" class="m-0 text-sm text-n-ruby-11">{{ error }}</p>
      <Button
        :label="t('FINANCIAL.STORE.PUBLICATION.RETRY')"
        icon="i-lucide-refresh-cw"
        variant="ghost"
        color="slate"
        :disabled="loading"
        @click="load"
      />
    </div>
  </div>
</template>
