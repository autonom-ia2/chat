// Re-evaluate, resume and re-check of an e-mail campaign, with the answer of the server kept
// until the campaign changes. Shared by the old Gestão (EmailCampaignHealth) and the
// Resultado (#990), so both run the same calls and show the same messages.
import { computed, ref, watch } from 'vue';
import EmailCampaignsAPI from 'dashboard/api/emailCampaigns';
import { NS, safeError, canResumeCampaign } from './presentation';

export function useEmailHealthActions(campaign, { t, onUpdated }) {
  const result = ref(null);
  const busy = ref(false);
  const errorMessage = ref('');
  const current = computed(() => result.value || campaign());

  watch(campaign, () => {
    result.value = null;
    errorMessage.value = '';
  });

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
      const updated = payload.campaign || payload;
      result.value = {
        ...updated,
        protection: payload.protection || updated.protection,
        preflight: payload.preflight || updated.preflight,
      };
      if (result.value.status === 'paused')
        errorMessage.value = t(`${NS}.STILL_BLOCKED`);
      onUpdated(result.value);
    } catch (error) {
      if (current.value.id === campaignId)
        errorMessage.value = safeError(t, error);
    } finally {
      busy.value = false;
    }
  };

  return { current, busy, errorMessage, act };
}
