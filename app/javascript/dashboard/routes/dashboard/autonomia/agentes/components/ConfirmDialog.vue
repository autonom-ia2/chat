<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  title: { type: String, required: true },
  description: { type: String, required: true },
  confirmLabel: { type: String, required: true },
  cancelLabel: { type: String, required: true },
  isLoading: { type: Boolean, default: false },
  destructive: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'close']);
const dialog = ref(null);
const open = () => dialog.value.open();
const close = () => dialog.value.close();
defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="title"
    :description="description"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @confirm="emit('confirm')"
    @close="emit('close')"
  >
    <template #footer>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          class="min-h-11 px-4 rounded-xl border border-n-strong text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="close"
        >
          {{ cancelLabel }}
        </button>
        <button
          type="submit"
          :disabled="isLoading"
          class="min-h-11 px-4 rounded-xl font-semibold disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            destructive
              ? 'bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4'
              : 'bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12'
          "
        >
          {{ confirmLabel }}
        </button>
      </div>
    </template>
  </Dialog>
</template>
