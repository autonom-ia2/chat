<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EmailProtectionPanel from './EmailProtectionPanel.vue';
import EmailHygieneSummary from './EmailHygieneSummary.vue';
import EmailImportIssues from './EmailImportIssues.vue';
import { useEmailHealthActions } from './useEmailHealthActions';
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
  <div class="flex flex-col min-w-0 gap-3">
    <EmailProtectionPanel
      :campaign="current"
      :busy="busy"
      @reevaluate="act('reevaluate')"
      @resume="act('resume')"
      @problems="emit('problems')"
    />
    <EmailHygieneSummary
      v-if="current.id || current.preflight"
      :preflight="current.preflight"
      :busy="busy"
      @recheck="act('recheck')"
      @issues="showIssues = !showIssues"
    />
    <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ errorMessage }}
    </p>
    <EmailImportIssues v-if="showIssues" :campaign-id="current.id" />
  </div>
</template>
