import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useAvailableCampaignChannels } from 'dashboard/components-next/CampaignJourney/useAvailableCampaignChannels';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';
import BrandKitsAPI from 'dashboard/api/brandKits';

// Kits of the account (#1076), shared by the Identidade visual tab, "Criar com IA", Nova campanha
// and the campaign list: one list in memory, loaded on first use and after each change.
const kits = ref([]);
const archivedCount = ref(0);
const googleFonts = ref([]);
const loaded = ref(false);
const loading = ref(false);

export const resetBrandKits = () => {
  kits.value = [];
  archivedCount.value = 0;
  googleFonts.value = [];
  loaded.value = false;
};

export function useBrandKits() {
  const globalConfig = useMapGetter('globalConfig/get');
  const canManage = useCanManage('campaign_manage');
  const { channels, features } = useAvailableCampaignChannels();

  // The tab and every link into it: flag on (BRAND_KITS_ENABLED) and e-mail connected.
  const isAvailable = computed(
    () =>
      globalConfig.value?.brandKitsEnabled === true &&
      features.value.emailCampaigns &&
      channels.value.includes(CAMPAIGN_CHANNELS.EMAIL)
  );
  const isEnabled = computed(
    () => globalConfig.value?.brandKitsEnabled === true
  );
  const defaultKit = computed(
    () => kits.value.find(kit => kit.is_default) || null
  );

  const fetchKits = async () => {
    loading.value = true;
    try {
      const { data } = await BrandKitsAPI.list();
      kits.value = data.payload || [];
      archivedCount.value = data.meta?.archived_count || 0;
      googleFonts.value = data.meta?.google_fonts || [];
      loaded.value = true;
    } finally {
      loading.value = false;
    }
  };

  const ensureKits = () =>
    loaded.value || loading.value ? Promise.resolve() : fetchKits();

  return {
    kits,
    archivedCount,
    googleFonts,
    loaded,
    loading,
    isAvailable,
    isEnabled,
    canManage,
    defaultKit,
    fetchKits,
    ensureKits,
  };
}
