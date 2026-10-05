<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';

// What the customer typed in the landing page form (#1011). Shown as captured:
// the form is the source of truth, not the WhatsApp text the customer may edit.
const props = defineProps({
  leadForm: { type: Object, default: null },
});
const { t, locale } = useI18n();
const fields = computed(() =>
  (props.leadForm?.fields || []).filter(
    field => field && String(field.value ?? '').trim()
  )
);
const capturedAt = computed(() =>
  relativeTimeFromISO(props.leadForm?.captured_at, locale.value)
);
</script>

<template>
  <div class="empty:hidden">
    <section
      v-if="fields.length"
      aria-labelledby="crm-card-lead-form-title"
      class="rounded-lg bg-n-alpha-1 p-3"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h3
          id="crm-card-lead-form-title"
          class="m-0 flex items-center gap-2 text-xs font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-clipboard-list size-4 text-n-slate-10"
            aria-hidden="true"
          />
          {{ t('CRM_KANBAN.DRAWER.LEAD_FORM_TITLE') }}
        </h3>
        <span v-if="capturedAt" class="text-xs text-n-slate-10">
          {{ t('CRM_KANBAN.DRAWER.LEAD_FORM_CAPTURED', { time: capturedAt }) }}
        </span>
      </div>
      <dl class="m-0 mt-2.5 grid gap-1.5 text-sm">
        <div
          v-for="(field, index) in fields"
          :key="`${field.key}-${index}`"
          class="grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] gap-3"
        >
          <dt
            class="truncate text-n-slate-11"
            :title="field.label || field.key"
          >
            {{ field.label || field.key }}
          </dt>
          <dd class="m-0 break-words text-n-slate-12">{{ field.value }}</dd>
        </div>
      </dl>
    </section>
  </div>
</template>
