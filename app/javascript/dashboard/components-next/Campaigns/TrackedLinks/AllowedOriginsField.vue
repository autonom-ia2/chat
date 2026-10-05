<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { originHost, parseAllowedOrigins } from './trackedLinkWebsite';

// The "site where the button lives" field, shared by the create dialog and the
// website panel. People paste what they see in the browser (a full page link or
// just the domain); the preview shows the site that will actually be accepted,
// so nobody has to know what an "origin" is.
const props = defineProps({
  id: { type: String, required: true },
  disabled: { type: Boolean, default: false },
  // Show validation only after the person left the field or tried to save.
  touched: { type: Boolean, default: false },
  hideLabel: { type: Boolean, default: false },
});
const emit = defineEmits(['blur']);
const text = defineModel({ type: String, default: '' });
const { t } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';

const parsed = computed(() => parseAllowedOrigins(text.value));
// Two lines can point to the same site (http and https on localhost): show it once.
const accepted = computed(() => [
  ...new Set(parsed.value.origins.map(originHost)),
]);
const error = computed(() => {
  if (!props.touched) return '';
  if (parsed.value.invalid.length) {
    return t(`${NS}.ORIGINS_INVALID`, {
      list: parsed.value.invalid.join(', '),
    });
  }
  if (parsed.value.isTooMany) return t(`${NS}.ORIGINS_TOO_MANY`);
  if (parsed.value.isEmpty) return t(`${NS}.ORIGINS_REQUIRED`);
  return '';
});
const hintId = computed(() => `${props.id}-hint`);
</script>

<template>
  <div class="grid gap-2">
    <label
      :for="id"
      class="text-sm font-medium"
      :class="hideLabel ? 'sr-only' : ''"
    >
      {{ t(`${NS}.ORIGINS_LABEL`) }}
    </label>
    <textarea
      :id="id"
      v-model="text"
      rows="2"
      spellcheck="false"
      autocapitalize="off"
      autocomplete="off"
      :placeholder="t(`${NS}.ORIGINS_PLACEHOLDER`)"
      :disabled="disabled"
      :aria-invalid="!!error"
      :aria-describedby="hintId"
      class="w-full rounded-lg border bg-n-solid-2 px-3 py-2.5 font-mono text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
      :class="error ? 'border-n-ruby-8' : 'border-n-weak'"
      @blur="emit('blur')"
    />
    <div :id="hintId" class="grid gap-2 text-xs leading-relaxed">
      <p v-if="error" role="alert" class="m-0 text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <p v-else class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.ORIGINS_HINT`) }}
      </p>
      <div
        v-if="accepted.length"
        data-testid="allowed-origins-preview"
        class="flex flex-wrap items-center gap-1.5"
      >
        <span class="text-n-slate-11">{{ t(`${NS}.ORIGINS_PREVIEW`) }}</span>
        <span
          v-for="host in accepted"
          :key="host"
          class="inline-flex items-center gap-1 rounded-full bg-n-teal-3 px-2 py-0.5 font-medium text-n-teal-11"
        >
          <span class="i-lucide-check size-3" aria-hidden="true" />
          {{ host }}
        </span>
      </div>
      <p class="m-0 text-xs text-n-slate-10">{{ t(`${NS}.ORIGINS_MULTI`) }}</p>
      <details class="group">
        <summary
          class="inline-flex min-h-11 cursor-pointer list-none items-center gap-1 rounded text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
        >
          <span class="i-lucide-shield-check size-3.5" aria-hidden="true" />
          {{ t(`${NS}.ORIGINS_WHY_TITLE`) }}
          <span
            class="i-lucide-chevron-down size-3 transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </summary>
        <p
          class="m-0 mt-1.5 rounded-lg bg-n-alpha-2 px-3 py-2 text-xs leading-relaxed text-n-slate-11"
        >
          {{ t(`${NS}.ORIGINS_WHY`) }}
        </p>
      </details>
    </div>
  </div>
</template>
