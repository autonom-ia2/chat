<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  KANBAN_ZOOM_MIN,
  KANBAN_ZOOM_MAX,
  KANBAN_ZOOM_DEFAULT,
  KANBAN_ZOOM_STEP,
  KANBAN_ZOOM_PRESETS,
} from '../helpers/kanbanZoom';

const props = defineProps({
  modelValue: { type: Number, default: KANBAN_ZOOM_DEFAULT },
  persistenceFailed: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const popover = ref(null);
const trigger = ref(null);
const panel = ref(null);
const id = useId();

const focusPanel = async () => {
  await nextTick();
  panel.value?.focus();
};
const restoreFocus = () => {
  if (panel.value?.contains(document.activeElement)) trigger.value?.focus();
};
const close = () => {
  popover.value?.hide();
  trigger.value?.focus();
};
const handleTab = event => {
  const buttons = [...panel.value.querySelectorAll('button:not(:disabled)')];
  const atStart =
    document.activeElement === panel.value ||
    document.activeElement === buttons[0];
  const atEnd = document.activeElement === buttons.at(-1);
  if ((event.shiftKey && atStart) || (!event.shiftKey && atEnd)) {
    event.preventDefault();
    close();
  }
};
const step = direction => {
  const value = props.modelValue + direction * KANBAN_ZOOM_STEP;
  if (value >= KANBAN_ZOOM_MIN && value <= KANBAN_ZOOM_MAX) {
    emit('update:modelValue', value);
  }
};
</script>

<template>
  <div class="shrink-0" data-kanban-zoom>
    <Popover
      ref="popover"
      align="end"
      disable-mobile-view
      :show-content-border="false"
      @show="focusPanel"
      @hide="restoreFocus"
    >
      <template #default="{ isOpen }">
        <button
          ref="trigger"
          type="button"
          class="inline-flex h-11 w-28 items-center justify-center gap-2 rounded-[0.625rem] !border !border-solid border-n-weak bg-n-surface-1 px-3 text-sm font-semibold tabular-nums text-n-slate-12 transition-colors hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="{ '!border-n-blue-7 ring-[0.1875rem] ring-n-blue-3': isOpen }"
          aria-haspopup="dialog"
          :aria-expanded="isOpen"
          :aria-controls="`${id}-panel`"
          :aria-label="t('CRM_KANBAN.ZOOM.TRIGGER', { value: modelValue })"
          :title="t('CRM_KANBAN.ZOOM.TITLE')"
        >
          <span class="i-lucide-zoom-in size-[1.125rem]" aria-hidden="true" />
          <span>{{ t('CRM_KANBAN.ZOOM.PERCENT', { value: modelValue }) }}</span>
          <span
            class="i-lucide-chevron-down size-3 text-n-slate-9"
            aria-hidden="true"
          />
        </button>
      </template>
      <template #content>
        <section
          :id="`${id}-panel`"
          ref="panel"
          role="dialog"
          tabindex="-1"
          :aria-labelledby="`${id}-title`"
          :aria-describedby="`${id}-description`"
          class="w-[18.375rem] max-w-[calc(100vw-2rem)] rounded-[0.875rem] border border-n-weak bg-n-surface-1 p-4 outline-none"
          @keydown.esc.stop.prevent="close"
          @keydown.tab="handleTab"
        >
          <h2
            :id="`${id}-title`"
            class="mb-1 text-[0.9375rem] font-bold leading-5 text-n-slate-12"
          >
            {{ t('CRM_KANBAN.ZOOM.TITLE') }}
          </h2>
          <p
            :id="`${id}-description`"
            class="mb-4 text-xs leading-4 text-n-slate-11"
          >
            {{ t('CRM_KANBAN.ZOOM.DESCRIPTION') }}
          </p>
          <div class="grid grid-cols-[2.75rem_1fr_2.75rem] items-center gap-2">
            <button
              type="button"
              class="flex size-11 items-center justify-center rounded-[0.625rem] !border !border-solid border-n-weak bg-n-slate-2 text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-40"
              :disabled="modelValue <= KANBAN_ZOOM_MIN"
              :aria-label="t('CRM_KANBAN.ZOOM.DECREASE')"
              @click="step(-1)"
            >
              <span class="i-lucide-minus size-5" aria-hidden="true" />
            </button>
            <output
              class="flex h-11 items-center justify-center rounded-[0.625rem] bg-n-slate-2 text-base font-bold tabular-nums text-n-slate-12"
              aria-live="polite"
              aria-atomic="true"
            >
              {{ t('CRM_KANBAN.ZOOM.PERCENT', { value: modelValue }) }}
            </output>
            <button
              type="button"
              class="flex size-11 items-center justify-center rounded-[0.625rem] !border !border-solid border-n-weak bg-n-slate-2 text-n-slate-12 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-40"
              :disabled="modelValue >= KANBAN_ZOOM_MAX"
              :aria-label="t('CRM_KANBAN.ZOOM.INCREASE')"
              @click="step(1)"
            >
              <span class="i-lucide-plus size-5" aria-hidden="true" />
            </button>
          </div>
          <div
            class="mt-3 grid grid-cols-5 gap-1.5"
            role="group"
            :aria-label="t('CRM_KANBAN.ZOOM.PRESETS')"
          >
            <button
              v-for="preset in KANBAN_ZOOM_PRESETS"
              :key="preset"
              type="button"
              class="min-h-11 rounded-[0.5625rem] !border !border-solid border-n-weak bg-n-surface-1 text-xs font-semibold tabular-nums text-n-slate-11 hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="{
                '!border-n-blue-7 !bg-n-blue-2 !text-n-blue-11':
                  modelValue === preset,
              }"
              :aria-pressed="modelValue === preset"
              @click="emit('update:modelValue', preset)"
            >
              {{ t('CRM_KANBAN.ZOOM.PERCENT', { value: preset }) }}
            </button>
          </div>
          <p
            class="mb-0 mt-3 flex items-start gap-1.5 text-[0.6875rem] leading-4 text-n-slate-11"
            role="status"
          >
            <span
              :class="
                persistenceFailed ? 'i-lucide-triangle-alert' : 'i-lucide-check'
              "
              class="mt-0.5 size-3 shrink-0"
              aria-hidden="true"
            />
            {{
              persistenceFailed
                ? t('CRM_KANBAN.ZOOM.SAVE_FAILED')
                : t('CRM_KANBAN.ZOOM.SAVED')
            }}
          </p>
        </section>
      </template>
    </Popover>
  </div>
</template>
