<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import EmailCampaignsAPI from 'dashboard/api/emailCampaigns';
import EmailProtectionPanel from './EmailProtectionPanel.vue';
import EmailHygieneSummary from './EmailHygieneSummary.vue';
import EmailImportIssues from './EmailImportIssues.vue';
import { NS, safeError, canResumeCampaign } from './presentation';
const props = defineProps({ campaign: { type: Object, required: true } });
const emit = defineEmits(['updated', 'problems']);
const { t } = useI18n();
const result = ref(null);
const busy = ref(false);
const errorMessage = ref('');
const showIssues = ref(false);
const current = computed(() => result.value || props.campaign);
watch(
  () => props.campaign,
  () => {
    result.value = null;
    errorMessage.value = '';
  }
);
const act = async action => {
  if (busy.value || !current.value.id) return;
  if (action === 'resume' && !canResumeCampaign(current.value)) return;
  const campaignId = current.value.id;
  busy.value = true;
  errorMessage.value = '';
  try {
    const { data } = await EmailCampaignsAPI[action](campaignId);
    if (current.value.id !== campaignId) return;
    const payload = data.payload;
    const campaign = payload.campaign || payload;
    result.value = {
      ...campaign,
      protection: payload.protection || campaign.protection,
      preflight: payload.preflight || campaign.preflight,
    };
    if (result.value.status === 'paused')
      errorMessage.value = t(`${NS}.STILL_BLOCKED`);
    emit('updated', result.value);
  } catch (error) {
    if (current.value.id === campaignId)
      errorMessage.value = safeError(t, error);
  } finally {
    busy.value = false;
  }
};
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
