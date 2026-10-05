<script setup>
// "Origem e campanhas" of the contact panel (#1002, PRD D20, §6.11, P1): every origin and
// campaign mark of the contact's conversations, in order, and the audiences the contact is
// in. While the request runs (or if it fails) it shows the marks of the open conversation.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignJourneyAPI from 'dashboard/api/campaignJourney';
import { buildCrmOrigin } from 'dashboard/routes/dashboard/crm/composables/useCrmOrigin';
import CrmOriginList from 'dashboard/routes/dashboard/crm/components/CrmOriginList.vue';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  // additional_attributes of the open conversation (campaign / campaign_touches).
  conversationAttributes: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const marks = ref(null);
const audiences = ref([]);
let requestSeq = 0;

const conversationMarks = computed(() => {
  const { campaign_touches: touches, campaign } = props.conversationAttributes;
  if (Array.isArray(touches)) return touches;
  return campaign ? [campaign] : [];
});

// Touches as the API sends them; CrmOriginList builds each origin with useCrmOrigin (#1037).
const touches = computed(() => marks.value ?? conversationMarks.value);
const origins = computed(() =>
  touches.value.map(buildCrmOrigin).filter(Boolean)
);

const load = async contactId => {
  requestSeq += 1;
  const seq = requestSeq;
  marks.value = null;
  audiences.value = [];
  if (!contactId) return;

  try {
    const { data } = await CampaignJourneyAPI.getContactOrigins(contactId);
    if (seq !== requestSeq) return;
    marks.value = data.payload?.marks || [];
    audiences.value = data.payload?.audiences || [];
  } catch {
    // Keeps the open conversation's marks; the panel never blocks on this.
  }
};

watch(() => props.contactId, load, { immediate: true });
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="origins.length || audiences.length"
    class="flex flex-col gap-2 px-2 pb-3"
    data-test-id="contact-origins-panel"
  >
    <h3 class="text-xs font-medium text-n-slate-11">
      {{ t('CRM_KANBAN.ORIGIN_JOURNEY.TITLE') }}
    </h3>
    <CrmOriginList v-if="origins.length" :campaigns="touches" />
    <div v-if="audiences.length" class="flex flex-col gap-1">
      <span class="text-xs text-n-slate-11">
        {{ t('CRM_KANBAN.ORIGIN_JOURNEY.AUDIENCES') }}
      </span>
      <ul class="flex flex-wrap gap-1" data-test-id="contact-audiences">
        <li
          v-for="audience in audiences"
          :key="audience.id"
          class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[11px] text-n-slate-12"
        >
          {{ audience.name }}
        </li>
      </ul>
    </div>
  </section>
</template>
