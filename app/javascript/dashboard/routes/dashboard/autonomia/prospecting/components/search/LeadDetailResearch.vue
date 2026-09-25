<script setup>
// Empresa e decisor no painel lateral do lead (#679), como o
// DecisionResearchPanel do Orth: botão Pesquisar / Verificar novamente /
// Pesquisando…, selos, Quem atende, motivo de não haver decisor, bloco Empresa
// e mensagens de bloqueio. O pedido sobe por evento; o resultado chega pelo
// evento prospecting.lead.updated, que troca o lead inteiro. Em Quem atende,
// cada sócio pode virar o decisor e o contato do lead (Usar como contato, #680).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ConfirmModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import LeadResearchBadge from './LeadResearchBadge.vue';
import LeadResearchCompany from './LeadResearchCompany.vue';
import {
  formatResearchDate,
  isResearchActive,
  noDecisionReasonKey,
  qualificationLabelKey,
  researchPhase,
} from '../../utils/leadResearch';

const props = defineProps({
  lead: { type: Object, required: true },
  researchEnabled: { type: Boolean, default: false },
  canManage: { type: Boolean, default: false },
  requesting: { type: Boolean, default: false },
  // Sócio sendo adotado como contato agora; vazio quando nenhum.
  adoptingOwnerName: { type: String, default: '' },
});

const emit = defineEmits(['research', 'adoptOwner']);

// Estados finais sem decisor em que a tela explica o motivo. Falha e bloqueio
// têm aviso próprio.
const NO_DECISION_STATES = ['confirmed', 'possible', 'ambiguous', 'no_result'];

const { t } = useI18n();
const retryConfirmModal = ref(null);

const research = computed(() => props.lead.research || {});
const phase = computed(() => researchPhase(research.value));
const isRunning = computed(
  () => props.requesting || isResearchActive(research.value)
);
const wasResearched = computed(() => phase.value !== 'none');
const owners = computed(() => research.value.owners || []);
const statuses = computed(() => [
  research.value.company_status,
  research.value.decision_status,
]);

const actionLabel = computed(() => {
  if (isRunning.value) return t('PROSPECTING.RESEARCH.PANEL.RUNNING');
  return wasResearched.value
    ? t('PROSPECTING.RESEARCH.PANEL.RETRY')
    : t('PROSPECTING.RESEARCH.PANEL.SEARCH');
});

const verifiedText = computed(() => {
  const date = formatResearchDate(research.value.verified_at);
  if (!date || isRunning.value || phase.value !== 'done') return '';
  return research.value.reused
    ? t('PROSPECTING.RESEARCH.PANEL.REUSED_ON', { date })
    : t('PROSPECTING.RESEARCH.PANEL.UPDATED_ON', { date });
});

const notice = computed(() => {
  if (!props.researchEnabled) return t('PROSPECTING.RESEARCH.PANEL.DISABLED');
  if (isRunning.value) return t('PROSPECTING.RESEARCH.PANEL.RUNNING_HINT');
  if (statuses.value.includes('failed')) {
    return t('PROSPECTING.RESEARCH.PANEL.FAILED');
  }
  if (statuses.value.includes('blocked')) {
    return t('PROSPECTING.RESEARCH.PANEL.BLOCKED');
  }
  if (!wasResearched.value) {
    return t('PROSPECTING.RESEARCH.PANEL.NEVER_RESEARCHED');
  }
  return '';
});

const noDecisionText = computed(() => {
  const showsReason =
    !isRunning.value &&
    !research.value.decision?.name &&
    NO_DECISION_STATES.includes(research.value.decision_status);
  return showsReason
    ? t(noDecisionReasonKey(research.value.no_decision_reason))
    : '';
});

const qualificationText = qualification => {
  const key = qualificationLabelKey(qualification);
  return key ? t(key) : qualification;
};

const sameName = (left, right) =>
  (left || '').trim().toLocaleUpperCase() ===
  (right || '').trim().toLocaleUpperCase();
// "Contato atual" compara com o contato real do lead (contact_name), não com o
// decisor: o contato pode ser de outro negócio com o mesmo telefone, ou um
// contato que o usuário já tinha. O decisor que não é o contato leva o selo
// Decisor.
const isCurrentContact = owner =>
  Boolean(props.lead.contact_name) &&
  sameName(owner.name, props.lead.contact_name);
const isDecision = owner =>
  Boolean(research.value.decision?.name) &&
  sameName(owner.name, research.value.decision.name);

const ownerLine = owner => {
  const qualification = qualificationText(owner.qualification);
  return qualification ? `${owner.name} · ${qualification}` : owner.name;
};

const requestResearch = async () => {
  if (!wasResearched.value) {
    emit('research', { force: false });
    return;
  }
  const confirmed = await retryConfirmModal.value?.showConfirmation();
  if (confirmed) emit('research', { force: true });
};
</script>

<template>
  <section
    data-test="lead-detail-research"
    class="grid gap-3 rounded-md border border-n-weak bg-n-solid-2 p-4"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('PROSPECTING.RESEARCH.PANEL.TITLE') }}
        </h3>
        <div class="mt-2 flex flex-wrap gap-1.5" aria-live="polite">
          <LeadResearchBadge kind="company" :status="research.company_status" />
          <LeadResearchBadge
            kind="decision"
            :status="research.decision_status"
          />
        </div>
        <p v-if="verifiedText" class="mt-2 text-xs text-n-slate-10">
          {{ verifiedText }}
        </p>
      </div>
      <button
        v-if="canManage"
        data-test="research-action"
        type="button"
        class="inline-flex min-h-11 items-center gap-2 rounded-md border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-3 disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isRunning || !researchEnabled"
        @click="requestResearch"
      >
        <span
          class="size-4"
          :class="
            isRunning
              ? 'i-lucide-loader-circle animate-spin motion-reduce:animate-none'
              : wasResearched
                ? 'i-lucide-rotate-cw'
                : 'i-lucide-search'
          "
          aria-hidden="true"
        />
        {{ actionLabel }}
      </button>
    </header>

    <p
      v-if="notice"
      class="rounded-md border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-11"
      aria-live="polite"
    >
      {{ notice }}
    </p>

    <section
      v-if="owners.length"
      data-test="research-owners"
      class="rounded-md border border-n-weak bg-n-solid-1 p-3"
    >
      <h4 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('PROSPECTING.RESEARCH.PANEL.OWNERS_TITLE') }}
      </h4>
      <ul class="mt-2 grid gap-1.5">
        <li
          v-for="owner in owners"
          :key="`${owner.name}-${owner.qualification}`"
          class="flex flex-wrap items-center justify-between gap-2"
        >
          <span
            data-test="research-owner-line"
            class="min-w-0 break-words text-sm font-medium text-n-slate-12"
          >
            {{ ownerLine(owner) }}
          </span>
          <span
            v-if="isCurrentContact(owner)"
            class="rounded-full bg-n-teal-2 px-2 py-0.5 text-xs font-medium text-n-teal-11 ring-1 ring-n-teal-5"
          >
            {{ t('PROSPECTING.RESEARCH.PANEL.CURRENT_CONTACT') }}
          </span>
          <span
            v-else-if="isDecision(owner)"
            class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11 ring-1 ring-n-weak"
          >
            {{ t('PROSPECTING.RESEARCH.PANEL.DECISION_OWNER') }}
          </span>
          <button
            v-else-if="canManage"
            type="button"
            class="inline-flex min-h-11 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-2 px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-3 disabled:cursor-not-allowed disabled:opacity-60"
            :aria-label="
              t('PROSPECTING.RESEARCH.PANEL.USE_AS_CONTACT_LABEL', {
                name: owner.name,
              })
            "
            :disabled="Boolean(adoptingOwnerName)"
            @click="emit('adoptOwner', owner)"
          >
            <span class="i-lucide-user-check size-3.5" aria-hidden="true" />
            {{
              adoptingOwnerName === owner.name
                ? t('PROSPECTING.RESEARCH.PANEL.ADOPTING')
                : t('PROSPECTING.RESEARCH.PANEL.USE_AS_CONTACT')
            }}
          </button>
        </li>
      </ul>
    </section>

    <p
      v-if="noDecisionText"
      data-test="research-no-decision"
      class="rounded-md border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-11"
    >
      {{ noDecisionText }}
    </p>

    <LeadResearchCompany :company="research.company" />

    <ConfirmModal
      ref="retryConfirmModal"
      :title="t('PROSPECTING.RESEARCH.PANEL.CONFIRM_TITLE')"
      :description="t('PROSPECTING.RESEARCH.PANEL.CONFIRM_DESCRIPTION')"
      :confirm-label="t('PROSPECTING.RESEARCH.PANEL.CONFIRM_ACTION')"
      :cancel-label="t('PROSPECTING.RESEARCH.PANEL.CANCEL')"
    />
  </section>
</template>
