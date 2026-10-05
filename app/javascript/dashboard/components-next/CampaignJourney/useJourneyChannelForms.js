// Data the WhatsApp API and e-mail forms of Nova campanha need (#993 front of #999): inboxes
// marked for campaigns and their saved templates, e-mail senders and reply inboxes, the e-mail
// draft once created, and the exact "vão receber" preview for every journey channel.
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import WhatsappApiMessageTemplatesAPI from 'dashboard/api/whatsappApiMessageTemplates';
import EmailCampaignsAPI from 'dashboard/api/emailCampaigns';
import { journeyCampaignsAPI } from 'dashboard/api/campaignJourney';
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import {
  BACKEND_CHANNEL,
  buildPreviewPayload,
  isWhatsappApiCampaignInbox,
} from './journeyChannelPayloads';

const PREVIEW_DELAY_MS = 400;

export function useJourneyChannelForms({ draft, bindings }) {
  const inboxes = useMapGetter('inboxes/getInboxes');
  const identities = useMapGetter('emailSenderIdentities/getIdentities');

  const apiTemplates = ref([]);
  const mediaFile = ref(null);
  const emailCampaign = ref(null);
  const preview = ref(null);
  let previewTimer = null;

  const apiInboxOptions = computed(() =>
    (inboxes.value || [])
      .filter(isWhatsappApiCampaignInbox)
      .map(inbox => ({ value: inbox.id, label: inbox.name }))
  );

  const loadApiTemplates = async inboxId => {
    apiTemplates.value = [];
    if (!inboxId || draft.value.channel !== CAMPAIGN_CHANNELS.WHATSAPP_API) {
      return;
    }
    try {
      const { data } =
        await WhatsappApiMessageTemplatesAPI.getTemplates(inboxId);
      apiTemplates.value = (data?.payload || []).filter(
        template => !template.archived_at
      );
    } catch {
      apiTemplates.value = [];
    }
  };

  const loadEmailCampaign = async () => {
    const id = draft.value.emailCampaignId;
    if (!id) {
      emailCampaign.value = null;
      return;
    }
    try {
      const { data } = await EmailCampaignsAPI.show(id);
      emailCampaign.value = data?.payload || data;
    } catch {
      emailCampaign.value = null;
    }
  };

  const refreshPreview = () => {
    window.clearTimeout(previewTimer);
    const audienceId = draft.value.audienceId;
    if (!audienceId || !BACKEND_CHANNEL[draft.value.channel]) {
      preview.value = null;
      return;
    }
    previewTimer = window.setTimeout(async () => {
      try {
        const { data } = await journeyCampaignsAPI.preview(
          buildPreviewPayload({
            audienceId,
            draft: draft.value,
            bindings: bindings(),
          })
        );
        preview.value = data?.payload || null;
      } catch {
        preview.value = null;
      }
    }, PREVIEW_DELAY_MS);
  };

  watch([() => draft.value.channel, () => draft.value.inboxId], ([, inboxId]) =>
    loadApiTemplates(inboxId)
  );
  watch(() => draft.value.emailCampaignId, loadEmailCampaign);
  watch(
    [
      () => draft.value.audienceId,
      () => draft.value.channel,
      () => draft.value.messageBody,
      () => JSON.stringify(draft.value.bindings),
      () => JSON.stringify(draft.value.defaults),
    ],
    refreshPreview
  );

  const stop = () => window.clearTimeout(previewTimer);

  return {
    apiInboxOptions,
    apiTemplates,
    mediaFile,
    identities,
    inboxes,
    emailCampaign,
    preview,
    loadApiTemplates,
    loadEmailCampaign,
    refreshPreview,
    stop,
  };
}
