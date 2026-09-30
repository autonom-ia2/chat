<script setup>
import { nextTick, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({ actions: { type: Array, required: true } });
const emit = defineEmits(['select']);
const trigger = ref(null);
const buttons = ref([]);
const focusFirst = () => nextTick(() => buttons.value[0]?.$el.focus());
const restoreFocus = () => nextTick(() => trigger.value?.$el.focus());
</script>

<template>
  <Popover @show="focusFirst" @hide="restoreFocus">
    <template #default="{ isOpen }">
      <Button
        ref="trigger"
        type="button"
        outline
        slate
        sm
        icon="i-lucide-ellipsis"
        class="min-h-11 min-w-11 w-full !px-3 xl:w-auto"
        :aria-label="$t('RELATIONSHIPS.MORE_ACTIONS')"
        :aria-expanded="isOpen"
      >
        <span class="xl:sr-only">{{ $t('RELATIONSHIPS.MORE_ACTIONS') }}</span>
      </Button>
    </template>
    <template #content="{ hide }">
      <div class="flex w-64 flex-col gap-1 p-2">
        <Button
          v-for="action in actions"
          :key="action.key"
          ref="buttons"
          type="button"
          ghost
          slate
          justify="start"
          class="min-h-11"
          :label="action.label"
          :icon="action.icon"
          :disabled="action.disabled"
          @click="
            hide();
            emit('select', action.key);
          "
        />
      </div>
    </template>
  </Popover>
</template>
