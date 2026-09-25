<script setup>
// Janela "Adicionar à campanha" a partir da seleção da busca (#680). Como no
// Orth (ACAO-25/37), a seleção vira um segmento: uma lista, uma etiqueta nos
// contatos e, se escolhida, a campanha de envio único ativa. Quem decide quem
// entra é o servidor; a janela mostra quem entrou e quem ficou de fora, com o
// motivo de cada lead (ACAO-26/27).
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';

const props = defineProps({
  leads: { type: Array, required: true },
  defaultSegmentName: { type: String, default: '' },
});

const emit = defineEmits(['close', 'done']);

// A janela cobre a tela inteira, inclusive o canto do lançador do Guia (#646).
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const titleId = useId();
const segmentFieldId = useId();

const campaigns = ref([]);
const campaignsFailed = ref(false);
const campaignId = ref('');
const segmentName = ref(props.defaultSegmentName);
const isSubmitting = ref(false);
const errorMessage = ref('');
const segment = ref(null);
// Recusa sem nenhum elegível: o servidor manda o motivo de cada lead mesmo assim.
const rejectedLeads = ref([]);

const campaignChoices = computed(() => [
  { value: '', label: t('PROSPECTING.CAMPAIGN_SELECTION.SEGMENT_ONLY') },
  ...campaigns.value
    .filter(
      campaign =>
        campaign.campaign_type === 'one_off' &&
        campaign.campaign_status === 'active'
    )
    .map(campaign => ({ value: campaign.id, label: campaign.title })),
]);
const canSubmit = computed(
  () => Boolean(segmentName.value.trim()) && !isSubmitting.value
);

// Códigos do servidor (CampaignSegmentBuilder e SelectionCampaignSegment).
// Código que a tela ainda não conhece usa o texto que o servidor mandou.
const BLOCK_REASONS = {
  no_phone: () => t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.NO_PHONE'),
  no_whatsapp: () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.NO_WHATSAPP'),
  opt_out: () => t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.OPT_OUT'),
  contact_blocked: () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.CONTACT_BLOCKED'),
  discarded: () => t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.DISCARDED'),
  not_ready: () => t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.NOT_READY'),
  not_found: () => t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.NOT_FOUND'),
};
const blockReason = lead =>
  BLOCK_REASONS[lead.reason_code]?.() ||
  lead.reason ||
  t('PROSPECTING.CAMPAIGN_SELECTION.BLOCK_REASONS.DEFAULT');
const blockedLabel = lead => {
  const name =
    lead.name ||
    t('PROSPECTING.CAMPAIGN_SELECTION.UNKNOWN_LEAD', { id: lead.id });
  return `${name} · ${blockReason(lead)}`;
};
const blockedLeads = computed(
  () => segment.value?.blocked_leads || rejectedLeads.value
);

const ERROR_CODES = {
  'prospecting.campaign.no_eligible_leads': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.NO_ELIGIBLE'),
  'prospecting.campaign.not_found': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.CAMPAIGN_NOT_FOUND'),
  'prospecting.campaign.campaign_not_active': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.CAMPAIGN_NOT_ACTIVE'),
  'prospecting.campaign.unsupported_campaign': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.UNSUPPORTED_CAMPAIGN'),
  'prospecting.campaign.label_collision_visible_on_sidebar': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.LABEL_COLLISION'),
  'prospecting.campaign.too_many_leads': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.TOO_MANY_LEADS'),
  'prospecting.campaign.empty_selection': () =>
    t('PROSPECTING.CAMPAIGN_SELECTION.ERRORS.EMPTY_SELECTION'),
};
// O servidor manda código em `error` nas recusas do segmento; texto livre
// (validação do modelo) aparece como veio.
const errorText = error => {
  const serverError = error?.response?.data?.error;
  return (
    ERROR_CODES[serverError]?.() ||
    serverError ||
    t('PROSPECTING.CAMPAIGN_SELECTION.ERROR')
  );
};

onMounted(async () => {
  try {
    const { data } = await CampaignsAPI.get();
    campaigns.value = data || [];
  } catch {
    campaignsFailed.value = true;
  }
});

const submit = async () => {
  if (!canSubmit.value) return;

  isSubmitting.value = true;
  errorMessage.value = '';
  rejectedLeads.value = [];
  try {
    const { data } = await AutonomiaProspectingAPI.addLeadsToCampaign({
      leadIds: props.leads.map(lead => lead.id),
      campaignId: campaignId.value,
      segmentName: segmentName.value.trim(),
    });
    segment.value = data.payload.segment;
    emit('done', segment.value);
  } catch (error) {
    errorMessage.value = errorText(error);
    rejectedLeads.value =
      error?.response?.data?.payload?.segment?.blocked_leads || [];
  } finally {
    isSubmitting.value = false;
  }
};

const close = () => {
  if (!isSubmitting.value) emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/30 px-4"
    @click.self="close"
  >
    <section
      role="dialog"
      aria-modal="true"
      :aria-labelledby="titleId"
      class="grid max-h-[90vh] w-full max-w-md gap-4 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 p-5 shadow-xl"
    >
      <header class="flex items-start justify-between gap-3">
        <h2 :id="titleId" class="text-base font-semibold text-n-slate-12">
          {{ t('PROSPECTING.CAMPAIGN_SELECTION.TITLE') }}
        </h2>
        <button
          type="button"
          data-test="campaign-close"
          class="flex size-11 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
          :aria-label="t('PROSPECTING.CAMPAIGN_SELECTION.CLOSE')"
          :disabled="isSubmitting"
          @click="close"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </header>

      <section
        v-if="segment"
        data-test="campaign-result"
        class="grid gap-3"
        aria-live="polite"
      >
        <ul class="grid gap-1 text-sm text-n-slate-12">
          <li>
            {{
              t('PROSPECTING.CAMPAIGN_SELECTION.RESULT.ELIGIBLE', {
                count: segment.eligible_count,
                label: segment.label.title,
              })
            }}
          </li>
          <li v-if="segment.campaign">
            {{
              t('PROSPECTING.CAMPAIGN_SELECTION.RESULT.CAMPAIGN', {
                title: segment.campaign.title,
              })
            }}
          </li>
          <li v-if="segment.created_contacts_count">
            {{
              t('PROSPECTING.CAMPAIGN_SELECTION.RESULT.CONTACTS_CREATED', {
                count: segment.created_contacts_count,
              })
            }}
          </li>
        </ul>
      </section>

      <template v-else>
        <p class="text-sm text-n-slate-12">
          {{
            t('PROSPECTING.CAMPAIGN_SELECTION.SELECTED', {
              count: leads.length,
            })
          }}
        </p>
        <p class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.CAMPAIGN_SELECTION.RULE') }}
        </p>
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('PROSPECTING.CAMPAIGN_SELECTION.CAMPAIGN') }}
          </span>
          <ChoiceSelect
            v-model="campaignId"
            :options="campaignChoices"
            :aria-label="t('PROSPECTING.CAMPAIGN_SELECTION.CAMPAIGN')"
            :disabled="isSubmitting"
          />
        </label>
        <p v-if="campaignsFailed" class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.CAMPAIGN_SELECTION.CAMPAIGNS_LOAD_ERROR') }}
        </p>
        <div class="grid gap-1">
          <label
            :for="segmentFieldId"
            class="text-xs font-medium text-n-slate-11"
          >
            {{ t('PROSPECTING.CAMPAIGN_SELECTION.SEGMENT_NAME') }}
          </label>
          <input
            :id="segmentFieldId"
            v-model="segmentName"
            type="text"
            class="h-11 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
            :disabled="isSubmitting"
          />
        </div>
        <p
          v-if="errorMessage"
          role="alert"
          class="rounded-md border border-n-ruby-5 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
        >
          {{ errorMessage }}
        </p>
      </template>

      <div v-if="blockedLeads.length" class="grid gap-2">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{
            t('PROSPECTING.CAMPAIGN_SELECTION.RESULT.BLOCKED', {
              count: blockedLeads.length,
            })
          }}
        </h3>
        <ul
          class="grid max-h-48 gap-1.5 overflow-y-auto rounded-md border border-n-weak bg-n-solid-2 p-3"
        >
          <li
            v-for="lead in blockedLeads"
            :key="lead.id"
            data-test="campaign-blocked"
            class="break-words text-sm text-n-slate-12"
          >
            {{ blockedLabel(lead) }}
          </li>
        </ul>
      </div>

      <footer class="flex justify-end gap-2">
        <template v-if="!segment">
          <button
            type="button"
            class="min-h-11 rounded-md px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="isSubmitting"
            @click="close"
          >
            {{ t('PROSPECTING.CAMPAIGN_SELECTION.CANCEL') }}
          </button>
          <button
            type="button"
            data-test="campaign-submit"
            class="min-h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="!canSubmit"
            @click="submit"
          >
            {{
              isSubmitting
                ? t('PROSPECTING.CAMPAIGN_SELECTION.SUBMITTING')
                : t('PROSPECTING.CAMPAIGN_SELECTION.SUBMIT')
            }}
          </button>
        </template>
        <button
          v-else
          type="button"
          class="min-h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white"
          @click="close"
        >
          {{ t('PROSPECTING.CAMPAIGN_SELECTION.CLOSE') }}
        </button>
      </footer>
    </section>
  </div>
</template>
