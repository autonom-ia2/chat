<script setup>
// "Análise dos destinatários ainda não enviados" of the Resultado (#990). Same counts and rules
// as the old Gestão block (EmailHygieneSummary, O1): only reconciled server counts are shown.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCanManage } from 'dashboard/composables/useCanManage';
import {
  NS as EMAIL_NS,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import {
  hygieneState,
  reconciledCounts,
} from 'dashboard/components-next/Campaigns/EmailProtection/hygieneCounts';

const props = defineProps({
  preflight: { type: Object, default: null },
  busy: Boolean,
});
const emit = defineEmits(['recheck', 'issues']);

const NS = 'RESULT_JOURNEY.EMAIL_HEALTH';
const { t, locale } = useI18n();
const canManage = useCanManage('campaign_manage');

const state = computed(() => hygieneState(props.preflight));
const counts = computed(() => reconciledCounts(props.preflight));

const PILL_CLASSES = {
  analysing: 'bg-n-blue-3 text-n-blue-11',
  completed: 'bg-n-teal-3 text-n-teal-11',
  ready: 'bg-n-teal-3 text-n-teal-11',
  protected: 'bg-n-alpha-2 text-n-slate-11',
  review: 'bg-n-amber-3 text-n-amber-11',
};
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    aria-live="polite"
    data-hygiene-card
  >
    <header class="flex flex-wrap items-start gap-3">
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-mail-search size-5" />
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="mb-0 text-base font-semibold text-n-slate-12">
            {{ t(`${NS}.HYGIENE_TITLE`) }}
          </h2>
          <span
            class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
            :class="PILL_CLASSES[state] || 'bg-n-alpha-2 text-n-slate-11'"
            data-hygiene-pill
          >
            {{ t(`${EMAIL_NS}.STATUS.${state}`) }}
          </span>
        </div>
        <p class="mb-0 max-w-2xl text-sm text-n-slate-11">
          {{ t(`${NS}.HYGIENE_TEXT`) }}
          {{ t(`${EMAIL_NS}.${counts ? 'CLASSIFICATION' : 'PENDING_COUNTS'}`) }}
        </p>
      </div>
    </header>

    <dl
      v-if="counts"
      class="m-0 grid grid-cols-2 gap-3 sm:grid-cols-4"
      data-hygiene-counts
    >
      <div
        v-for="item in counts"
        :key="item.key"
        class="min-w-0 rounded-xl border border-n-weak px-4 py-3"
        :data-count="item.key"
      >
        <dt class="text-xs text-n-slate-11">
          {{ t(`${EMAIL_NS}.STATUS.${item.key}`) }}
        </dt>
        <dd class="m-0 mt-1 text-xl font-semibold tabular-nums text-n-slate-12">
          {{ formatNumber(item.value, locale) }}
        </dd>
      </div>
    </dl>

    <div
      v-if="
        (canManage && preflight?.can_recheck) || preflight?.issues_count > 0
      "
      class="flex flex-col gap-2 sm:flex-row sm:flex-wrap"
    >
      <Button
        v-if="canManage && preflight?.can_recheck"
        :label="t(`${EMAIL_NS}.RECHECK`)"
        icon="i-lucide-refresh-cw"
        slate
        outline
        class="!min-h-11 !rounded-xl"
        :disabled="busy"
        :is-loading="busy"
        data-hygiene-action="recheck"
        @click="emit('recheck')"
      />
      <Button
        v-if="preflight?.issues_count > 0"
        :label="t(`${EMAIL_NS}.ISSUES`)"
        icon="i-lucide-list-filter"
        slate
        ghost
        class="!min-h-11 !rounded-xl"
        data-hygiene-action="issues"
        @click="emit('issues')"
      />
    </div>
  </section>
</template>
