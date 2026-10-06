<script setup>
// "Gestão de campanhas" (#1007, PRD D18): with CAMPAIGN_JOURNEY_ENABLED on it is the multichannel
// overview, and the e-mail detail it used to show lives in each e-mail Resultado; with the flag
// off the old page opens exactly as before (A5). Same route, same menu entry.
import { defineAsyncComponent } from 'vue';
import { isCampaignJourneyEnabled } from './campaignJourney.routes';

const page = isCampaignJourneyEnabled()
  ? defineAsyncComponent(() => import('./CampaignOverviewPage.vue'))
  : defineAsyncComponent(
      () => import('../../crm/pages/CrmCampaignManagementPage.vue')
    );
</script>

<template>
  <component :is="page" />
</template>
