<script setup>
import { computed, nextTick, ref, watch, useId } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

const props = defineProps({
  options: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
});
const emit = defineEmits(['search', 'retry', 'close']);
const model = defineModel({ type: String, default: '' });
const query = ref('');
const selectedName = ref('');
const trigger = ref(null);
const inputId = useId();
const selected = computed(() =>
  props.options.find(option => option.value === model.value)
);
watch(
  [model, selected],
  () => {
    if (!model.value) selectedName.value = '';
    else if (selected.value) selectedName.value = selected.value.label;
  },
  { immediate: true }
);
const select = (option, hide) => {
  selectedName.value = option.label;
  model.value = option.value;
  hide();
};
const close = async () => {
  query.value = '';
  emit('close');
  await nextTick();
  trigger.value?.$el.focus();
};
</script>

<template>
  <div class="min-w-0 [&>span]:w-full">
    <Popover align="start" @show="emit('search', '')" @hide="close">
      <template #default="{ isOpen }">
        <Button
          ref="trigger"
          type="button"
          outline
          slate
          justify="start"
          class="w-full min-h-11"
          icon="i-lucide-user-round"
          :aria-expanded="isOpen"
          :aria-label="$t('RELATIONSHIPS.CONTACTS')"
          :label="
            model
              ? selectedName || $t('RELATIONSHIPS.MEDIA.CONTACT_SELECTED')
              : $t('RELATIONSHIPS.MEDIA.ALL_CONTACTS')
          "
        />
      </template>
      <template #content="{ hide }">
        <div
          data-relationships-media-popover
          class="flex w-72 max-w-full flex-col gap-2 p-3"
        >
          <Input
            :id="inputId"
            v-model="query"
            autofocus
            type="search"
            :label="$t('RELATIONSHIPS.MEDIA.CONTACT_SEARCH')"
            @keydown.enter.prevent
            @update:model-value="emit('search', $event)"
          />
          <Button
            type="button"
            ghost
            slate
            justify="start"
            class="min-h-11"
            :label="$t('RELATIONSHIPS.MEDIA.ALL_CONTACTS')"
            @click="select({ value: '', label: '' }, hide)"
          />
          <p v-if="loading" role="status" class="m-0 text-sm text-n-slate-11">
            {{ $t('RELATIONSHIPS.LOADING') }}
          </p>
          <div v-else-if="error" role="alert" class="text-sm text-n-slate-11">
            <p>{{ $t('RELATIONSHIPS.MEDIA.CONTACT_ERROR') }}</p>
            <Button
              type="button"
              sm
              faded
              :label="$t('RELATIONSHIPS.RETRY')"
              @click="emit('retry')"
            />
          </div>
          <div v-else class="max-h-56 overflow-y-auto">
            <Button
              v-for="option in options"
              :key="option.value"
              type="button"
              ghost
              slate
              justify="start"
              class="w-full min-h-11"
              :label="option.label"
              :title="option.label"
              :aria-pressed="model === option.value"
              @click="select(option, hide)"
            />
            <p
              v-if="!options.length"
              role="status"
              class="m-0 p-2 text-sm text-n-slate-11"
            >
              {{ $t('RELATIONSHIPS.MEDIA.NO_CONTACTS') }}
            </p>
          </div>
        </div>
      </template>
    </Popover>
  </div>
</template>
