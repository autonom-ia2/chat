import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { connectedCampaignChannels } from './campaignChannels';

// PRD §8.10: channels the account can create campaigns on. Feeds the "Nova campanha"
// chooser; the list filter adds channels that still have campaigns (see campaignRows.js).
// E-mail only counts with a verified domain or a webmail inbox accepted for direct send,
// the same senders EmailCampaignDialog offers (emailSenders.js).
export function useAvailableCampaignChannels() {
  const inboxes = useMapGetter('inboxes/getInboxes');
  const identities = useMapGetter('emailSenderIdentities/getIdentities');
  const globalConfig = useMapGetter('globalConfig/get');
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );

  const features = computed(() => ({
    emailCampaigns:
      globalConfig.value?.emailCampaignEnabled === true &&
      globalConfig.value?.crmKanbanEnabled === true,
    whatsappCampaigns: isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.WHATSAPP_CAMPAIGNS
    ),
    whatsappApiCampaigns:
      globalConfig.value?.whatsappApiCampaignsEnabled === true,
  }));

  const channels = computed(() =>
    connectedCampaignChannels({
      inboxes: inboxes.value || [],
      senderIdentities: identities.value || [],
      features: features.value,
    })
  );

  return { channels, features };
}
