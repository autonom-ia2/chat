<script setup>
// Health of an e-mail send inside the Resultado (#990). Same data and actions as the old
// Gestão block (EmailCampaignHealth, O1) — re-evaluate, resume, re-check, problem list and
// import issues — drawn in the layout of the result pages.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EmailImportIssues from 'dashboard/components-next/Campaigns/EmailProtection/EmailImportIssues.vue';
import { useEmailHealthActions } from 'dashboard/components-next/Campaigns/EmailProtection/useEmailHealthActions';
import ResultProtectionCard from './ResultProtectionCard.vue';
import ResultHygieneCard from './ResultHygieneCard.vue';

const props = defineProps({ campaign: { type: Object, required: true } });
const emit = defineEmits(['updated', 'problems']);
const { t } = useI18n();
const showIssues = ref(false);
const { current, busy, errorMessage, act } = useEmailHealthActions(
  () => props.campaign,
  { t, onUpdated: value => emit('updated', value) }
);
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4" data-email-health>
    <ResultProtectionCard
      :campaign="current"
      :busy="busy"
      @reevaluate="act('reevaluate')"
      @resume="act('resume')"
      @problems="emit('problems')"
    />
    <p
      v-if="errorMessage"
      role="alert"
      class="m-0 rounded-xl border border-n-ruby-6 bg-n-solid-1 px-4 py-3 text-sm text-n-ruby-11"
      data-health-error
    >
      {{ errorMessage }}
    </p>
    <ResultHygieneCard
      v-if="current.id || current.preflight"
      :preflight="current.preflight"
      :busy="busy"
      @recheck="act('recheck')"
      @issues="showIssues = !showIssues"
    />
    <EmailImportIssues v-if="showIssues" :campaign-id="current.id" />
  </div>
</template>
