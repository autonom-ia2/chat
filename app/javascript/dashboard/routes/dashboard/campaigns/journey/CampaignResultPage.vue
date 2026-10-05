<script setup>
// Resultado of one campaign (#1007, PRD §6.5, D18): e-mail reads the e-mail reports engine; WhatsApp
// Oficial, WhatsApp API and SMS read their recipients. Opened from "Abrir" in Campanha and from a
// row of Gestão de campanhas.
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { CAMPAIGN_CHANNELS } from 'dashboard/components-next/CampaignJourney/campaignChannels';
import EmailResultView from 'dashboard/components-next/CampaignResult/EmailResultView.vue';
import MessageResultView from 'dashboard/components-next/CampaignResult/MessageResultView.vue';

const route = useRoute();
const channel = computed(() => String(route.params.channel || ''));
const campaignId = computed(() => String(route.params.campaignId || ''));
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <EmailResultView
        v-if="channel === CAMPAIGN_CHANNELS.EMAIL"
        :key="`email-${campaignId}`"
        :campaign-id="campaignId"
      />
      <MessageResultView
        v-else-if="campaignId"
        :key="`${channel}-${campaignId}`"
        :channel="channel"
        :campaign-id="campaignId"
      />
    </div>
  </section>
</template>
