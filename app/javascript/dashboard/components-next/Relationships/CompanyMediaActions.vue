<script setup>
import { nextTick, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

const emit = defineEmits(['preview', 'download', 'origin']);
const trigger = ref(null);
const firstAction = ref(null);
const focusAction = async () => {
  await nextTick();
  firstAction.value?.$el.focus();
};
const restoreFocus = async () => {
  await nextTick();
  trigger.value?.$el.focus();
};
</script>

<template>
  <div class="flex shrink-0 items-center gap-1">
    <Button
      type="button"
      sm
      faded
      class="min-h-11"
      :label="$t('RELATIONSHIPS.MEDIA.PREVIEW')"
      @click="emit('preview')"
    />
    <Popover @show="focusAction" @hide="restoreFocus">
      <template #default="{ isOpen }">
        <Button
          ref="trigger"
          type="button"
          ghost
          slate
          class="min-h-11 min-w-11"
          icon="i-lucide-ellipsis"
          :aria-expanded="isOpen"
          :aria-label="$t('RELATIONSHIPS.MEDIA.ACTIONS')"
        />
      </template>
      <template #content="{ hide }">
        <div
          data-relationships-media-popover
          class="flex w-56 flex-col gap-1 p-2"
        >
          <Button
            ref="firstAction"
            type="button"
            ghost
            slate
            justify="start"
            class="min-h-11"
            icon="i-lucide-download"
            :label="$t('RELATIONSHIPS.MEDIA.DOWNLOAD')"
            @click="
              hide();
              emit('download');
            "
          />
          <Button
            type="button"
            ghost
            slate
            justify="start"
            class="min-h-11"
            icon="i-lucide-message-square"
            :label="$t('RELATIONSHIPS.MEDIA.ORIGIN')"
            @click="
              hide();
              emit('origin');
            "
          />
        </div>
      </template>
    </Popover>
  </div>
</template>
