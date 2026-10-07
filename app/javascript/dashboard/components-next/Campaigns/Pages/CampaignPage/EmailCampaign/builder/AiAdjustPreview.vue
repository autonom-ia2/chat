<script setup>
// Before/after of "Ajustar com IA" (#1095): nothing changes in the editor until the person applies. Side by
// side on wide screens, one at a time with a toggle on narrow ones. An adjusted e-mail over Gmail's 102 KB
// clip limit cannot be applied: the end of it would be cut in the inbox.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  beforeHtml: { type: String, required: true },
  afterHtml: { type: String, required: true },
  summary: { type: String, default: '' },
});

const emit = defineEmits(['apply', 'discard']);

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = key => t(`CAMPAIGN.EMAIL_CAMPAIGN.AI.ADJUST_PREVIEW.${key}`);

const GMAIL_CLIP_BYTES = 102 * 1024;
const VIEWS = ['before', 'after'];

const view = ref('after');
const applyButton = ref(null);

const tooLarge = computed(
  () => new TextEncoder().encode(props.afterHtml).length > GMAIL_CLIP_BYTES
);

const panels = computed(() => [
  { key: 'before', html: props.beforeHtml, label: tk('BEFORE') },
  { key: 'after', html: props.afterHtml, label: tk('AFTER') },
]);

onMounted(() => {
  applyButton.value?.$el?.focus?.();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-2 sm:p-4"
    @keydown.esc="emit('discard')"
  >
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="ai-adjust-preview-title"
      class="flex h-[min(56rem,calc(100dvh-1rem))] w-[min(80rem,calc(100vw-1rem))] min-w-0 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-xl"
      data-test="ai-adjust-preview"
    >
      <div class="flex flex-col gap-3 border-b border-n-weak px-5 py-4 sm:px-6">
        <div class="min-w-0">
          <h3
            id="ai-adjust-preview-title"
            class="mb-1 text-lg font-semibold leading-7 text-n-slate-12"
          >
            {{ tk('TITLE') }}
          </h3>
          <p class="mb-0 text-sm leading-5 text-n-slate-11">
            {{ tk('SUBTITLE') }}
          </p>
        </div>
        <p
          v-if="summary"
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-teal-3 px-3 py-2.5 text-sm leading-5 text-n-teal-12"
          data-test="ai-adjust-summary"
        >
          <span class="i-lucide-sparkles mt-0.5 size-4 shrink-0" />
          <span>{{ summary }}</span>
        </p>
        <div
          class="grid grid-cols-2 gap-1 rounded-xl bg-n-alpha-1 p-1 lg:hidden"
          role="group"
          :aria-label="tk('TOGGLE')"
        >
          <Button
            v-for="option in VIEWS"
            :key="option"
            :label="tk(option.toUpperCase())"
            slate
            :variant="view === option ? 'solid' : 'ghost'"
            :aria-pressed="view === option"
            class="!min-h-11 w-full !rounded-lg"
            :data-test="`ai-adjust-view-${option}`"
            @click="view = option"
          />
        </div>
      </div>

      <div
        class="grid min-h-0 flex-1 grid-cols-1 gap-4 bg-n-alpha-1 p-3 sm:p-4 lg:grid-cols-2"
      >
        <section
          v-for="panel in panels"
          :key="panel.key"
          class="min-h-0 flex-col gap-2"
          :class="view === panel.key ? 'flex' : 'hidden lg:flex'"
          :data-test="`ai-adjust-panel-${panel.key}`"
        >
          <span
            class="hidden w-fit items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium lg:inline-flex"
            :class="
              panel.key === 'after'
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            <span
              v-if="panel.key === 'after'"
              class="i-lucide-sparkles size-3.5"
            />
            {{ panel.label }}
          </span>
          <iframe
            :srcdoc="panel.html"
            sandbox=""
            referrerpolicy="no-referrer"
            :title="panel.label"
            class="min-h-0 w-full flex-1 rounded-xl border border-n-weak bg-white"
          />
        </section>
      </div>

      <div
        class="flex flex-col gap-3 border-t border-n-weak px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6"
      >
        <p
          v-if="tooLarge"
          class="mb-0 flex items-start gap-2 text-sm leading-5 text-n-ruby-11"
          data-test="ai-adjust-too-large"
        >
          <span class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0" />
          {{ tk('TOO_LARGE') }}
        </p>
        <p v-else class="mb-0 text-sm leading-5 text-n-slate-11">
          {{ tk('UNDO_HINT') }}
        </p>
        <div class="flex shrink-0 flex-col-reverse gap-2 sm:flex-row">
          <Button
            :label="tk('DISCARD')"
            slate
            faded
            class="!min-h-11 !rounded-xl"
            data-test="ai-adjust-discard"
            @click="emit('discard')"
          />
          <Button
            ref="applyButton"
            :label="tk('APPLY')"
            icon="i-lucide-check"
            class="!min-h-11 !rounded-xl"
            :disabled="tooLarge"
            data-test="ai-adjust-apply"
            @click="emit('apply')"
          />
        </div>
      </div>
    </div>
  </div>
</template>
