<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { dateFormat } from 'shared/helpers/timeHelper';

import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import CardLabels from 'dashboard/components-next/Conversation/ConversationCard/CardLabels.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';
import { useCrmOrigin } from '../composables/useCrmOrigin';
import CrmCardPill from './CrmCardPill.vue';
import {
  buildCrmCardIdentity,
  crmCardIdentityLabel,
} from './list/cardIdentity.js';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  // Stage accent hex (e.g. '#22c55e). Slate fallback when absent.
  stageColor: {
    type: String,
    default: '',
  },
  // Standalone variant renders a minimal card (used outside the board v-for).
  standalone: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['open', 'openConversation']);

const { t, locale } = useI18n();
const { originFromCampaigns, humanizedOriginLabel, formatOriginTitle } =
  useCrmOrigin();

const STAGE_FALLBACK_COLOR = '#64748b';

const railStyle = computed(() => ({
  backgroundColor: props.stageColor || STAGE_FALLBACK_COLOR,
}));

// The card payload owns the company association. Do not fall back to
// contact.company: the same contact can be shared by opportunities from
// different companies, so that snapshot can identify the wrong customer.
// Same identity rules as the List (cardIdentity.js):
//   B2B: company → person → business
//   B2C: person → business
//   standalone: business/title → no linked contact
const identity = computed(() =>
  buildCrmCardIdentity(props.card, t('CRM_KANBAN.CARD.STANDALONE'))
);
const identityAriaName = computed(() =>
  crmCardIdentityLabel(props.card, t('CRM_KANBAN.CARD.STANDALONE'))
);
const companyName = computed(() => identity.value.company);
const identityMain = computed(() => identity.value.main);
const identityPerson = computed(() => identity.value.person);
const identityBusiness = computed(() => identity.value.business);
const hasContact = computed(() => Boolean(props.card.contact));
const identityIcon = computed(() => {
  if (companyName.value) return 'i-lucide-building-2';
  if (hasContact.value) return 'i-lucide-user-round';
  return 'i-lucide-kanban-square';
});

// The responsible is a separate operational signal. It must never be used as
// the customer's avatar or identity, especially when the responsible is a bot.
const responsibleType = computed(() => props.card.responsible?.type || 'none');
const responsibleIsBot = computed(() => responsibleType.value === 'bot');
const responsibleName = computed(
  () => props.card.responsible?.name || t('CRM_KANBAN.CARD.NO_OWNER')
);
const responsibleLabel = computed(() => {
  if (!responsibleIsBot.value) return responsibleName.value;
  return t('CRM_KANBAN.CARD.RESPONSIBLE_AI', {
    name: responsibleName.value,
  });
});
const responsibleIcon = computed(() => {
  if (responsibleType.value === 'bot') return 'i-lucide-bot';
  if (responsibleType.value === 'agent') return 'i-lucide-user-round';
  return 'i-lucide-user-round-x';
});

// Demote priority to a small glyph, only for high/urgent (reuse the
// shared CardPriorityIcon).
const showPriorityGlyph = computed(() =>
  ['high', 'urgent'].includes(props.card.priority)
);

const valueLabel = computed(() => {
  const cents = Number(props.card.value_cents || 0);
  if (!cents) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: props.card.currency || 'BRL',
  }).format(cents / 100);
});

// Faixas do score, em sincronia com Crm::Ai::ScoreCalculator::TIERS (19/54/83/100).
// Ícone por faixa (não só cor) para a leitura não depender de percepção de cor.
const SCORE_TIERS = [
  {
    max: 19,
    key: 'COLD',
    icon: 'i-lucide-snowflake',
    filled: 'bg-n-alpha-2 text-n-slate-11',
    outlined: 'text-n-slate-11 ring-1 ring-inset ring-n-slate-8',
  },
  {
    max: 54,
    key: 'WARM',
    icon: 'i-lucide-thermometer',
    filled: 'bg-n-blue-3 text-n-blue-11',
    outlined: 'text-n-blue-11 ring-1 ring-inset ring-n-blue-8',
  },
  {
    max: 83,
    key: 'HOT',
    icon: 'i-lucide-flame',
    filled: 'bg-n-amber-3 text-n-amber-11',
    outlined: 'text-n-amber-11 ring-1 ring-inset ring-n-amber-8',
  },
  {
    max: 100,
    key: 'URGENT',
    icon: 'i-lucide-zap',
    // Único tom sólido: em fundo claro, ruby-3 lia mais fraco que o âmbar da faixa de baixo e
    // invertia a hierarquia. A faixa mais crítica é a única coisa no card que pode gritar.
    filled: 'bg-n-ruby-9 text-white',
    outlined: 'text-n-ruby-11 ring-1 ring-inset ring-n-ruby-8',
  },
];

// Nota escrita à mão aparece vazada (contorno) em vez de preenchida: dá para ver de relance quais
// scores são humanos sem abrir o card. Ela entra na ordenação igual, só a origem muda.
const scoreView = computed(() => {
  const value = Number(props.card.score || 0);
  if (!value || value <= 0) return null;

  const meta = props.card.metadata?.ai?.score || {};
  const tier = SCORE_TIERS.find(item => value <= item.max);
  // The board and list payloads may expose this as a flat field while the
  // drawer keeps it inside metadata. Only explicit provenance gets a label;
  // responsible bot/AI is never evidence that the score came from AI.
  const source =
    props.card.score_source || props.card.scoreSource || meta.source || '';
  const isManual = source === 'manual';
  // Chaves literais: o projeto proíbe chave de i18n montada dinamicamente.
  const tierLabel = {
    COLD: t('CRM_KANBAN.CARD.SCORE_TIER.COLD'),
    WARM: t('CRM_KANBAN.CARD.SCORE_TIER.WARM'),
    HOT: t('CRM_KANBAN.CARD.SCORE_TIER.HOT'),
    URGENT: t('CRM_KANBAN.CARD.SCORE_TIER.URGENT'),
  }[tier.key];

  let label = t('CRM_KANBAN.CARD.SCORE_UNSPECIFIED', { score: value });
  if (source === 'ai') {
    label = t('CRM_KANBAN.CARD.SCORE_AI', { score: value });
  } else if (source === 'manual') {
    label = t('CRM_KANBAN.CARD.SCORE_MANUAL', { score: value });
  }

  return {
    value,
    reason: meta.reason || '',
    icon: isManual ? 'i-lucide-hand' : tier.icon,
    toneClasses: isManual ? tier.outlined : tier.filled,
    label,
    ariaLabel: t('CRM_KANBAN.CARD.SCORE_ARIA', {
      score: value,
      tier: tierLabel,
      reason: meta.reason || tierLabel,
    }),
  };
});

const aiSuggestionLabel = computed(() => {
  const suggestion = props.card.ai_suggestion;
  if (!suggestion?.to_stage_name) return '';
  return t('CRM_KANBAN.AI_CARD.BADGE', { stage: suggestion.to_stage_name });
});

// Format the timestamp itself, never parse translated natural-language text.
// Short localized units keep the responsible readable in the compact footer.
const RELATIVE_TIME_UNITS = [
  { unit: 'year', seconds: 365 * 24 * 60 * 60 },
  { unit: 'month', seconds: 30 * 24 * 60 * 60 },
  { unit: 'day', seconds: 24 * 60 * 60 },
  { unit: 'hour', seconds: 60 * 60 },
  { unit: 'minute', seconds: 60 },
  { unit: 'second', seconds: 1 },
];
const localizedRelativeLabel = epoch => {
  const seconds = epoch - Date.now() / 1000;
  const { unit, seconds: duration } =
    RELATIVE_TIME_UNITS.find(item => Math.abs(seconds) >= item.seconds) ||
    RELATIVE_TIME_UNITS.at(-1);
  return new Intl.RelativeTimeFormat(
    (locale?.value || 'en').split('_').join('-'),
    { style: 'short', numeric: 'auto' }
  ).format(Math.round(seconds / duration), unit);
};

// Board timestamps are epoch seconds; keep conversion explicit.
const relativeFromEpoch = epoch => {
  const value = Number(epoch);
  if (!value || Number.isNaN(value)) return '';
  return localizedRelativeLabel(value);
};

const titleFromEpoch = epoch => {
  const value = Number(epoch);
  if (!value || Number.isNaN(value)) return '';
  return dateFormat(value, 'MMM d, yyyy h:mm a');
};

const lastMessageLabel = computed(() =>
  relativeFromEpoch(props.card.last_message_at)
);

const lastMessageTitle = computed(() =>
  titleFromEpoch(props.card.last_message_at)
);

// SLACardLabel expects the conversation-list "chat" shape; card.conversation
// already carries applied_sla + epoch fields from the payload builder.
const slaChat = computed(() => {
  const conversation = props.card?.conversation;
  if (!conversation?.applied_sla) return null;
  return {
    applied_sla: conversation.applied_sla,
    first_reply_created_at: conversation.first_reply_created_at,
    waiting_since: conversation.waiting_since,
    status: conversation.status,
  };
});

const followUp = computed(() => {
  const epoch = Number(props.card.next_follow_up_at);
  if (!epoch || Number.isNaN(epoch)) return null;

  const nowSeconds = Date.now() / 1000;
  const secondsUntil = epoch - nowSeconds;
  let tone = 'default';
  if (secondsUntil < 0) {
    tone = 'ruby';
  } else if (secondsUntil <= 24 * 60 * 60) {
    tone = 'amber';
  }

  // The nearest follow-up can be the AI cadence or a manual reminder; the badge
  // shows whichever is closest to due (per the locked decision) but flags its
  // type with an icon + tooltip so the two are never confused.
  const isAi = props.card.next_follow_up_source === 'ai';
  return {
    label: localizedRelativeLabel(epoch),
    title: isAi
      ? t('CRM_KANBAN.CARD.FOLLOW_UP_AI')
      : t('CRM_KANBAN.CARD.FOLLOW_UP_MANUAL'),
    icon: isAi ? 'i-lucide-bot' : 'i-lucide-calendar-clock',
    tone,
  };
});

// Etiquetas normais da conversa PRIMÁRIA (card.labels = array de titles);
// CardLabels resolve cor/truncagem cruzando com as labels da conta no store
// (mesmo padrão da lista de Conversas), evitando prop-drilling pelo board.
const accountLabels = useMapGetter('labels/getLabels');

// Etiquetas de CAMPANHA vivem só no Contato (CampaignImports::Importer), nunca
// sincronizadas para a conversa — mescladas aqui (mesmo chip do CardLabels,
// deduplicadas) para ficarem visíveis no card sem tocar no LabelBox da conversa.
const mergedLabels = computed(() => [
  ...new Set([
    ...(props.card.labels || []),
    ...(props.card.contact_labels || []),
  ]),
]);

// Pill de origem universal (card.campaigns = toques agregados, 1º toque primeiro).
// Texto = label humanizado do 1º toque; tooltip lista as URLs quando disponíveis;
// "+N" sinaliza os toques além do primeiro.
const campaignPill = computed(() => {
  return originFromCampaigns(props.card.campaigns);
});

// Convite de handoff em aberto (payload handoff_invite): âmbar dentro do
// prazo de pega, ruby quando o prazo estourou. Some quando o ciclo fecha
// (alguém pega, expira ou escala).
const handoffInvite = computed(() => {
  const due = Number(props.card?.handoff_invite?.pickup_due_at);
  if (!due || Number.isNaN(due)) return null;

  const isOverdue = Date.now() / 1000 > due;
  return {
    tone: isOverdue ? 'ruby' : 'amber',
    label: localizedRelativeLabel(due),
    title: isOverdue
      ? t('CRM_KANBAN.CARD.HANDOFF_INVITE_OVERDUE')
      : t('CRM_KANBAN.CARD.HANDOFF_INVITE_PENDING'),
  };
});

// Board card carries the primary conversation's per-account display_id (same
// field the drawer navigates by). When present on a board card, the last-message
// bubble doubles as a shortcut straight into the inbox conversation; otherwise it
// stays a plain, non-interactive label (manual/standalone cards have no thread).
const conversationDisplayId = computed(
  () => props.card?.conversation?.display_id || ''
);
const canOpenConversation = computed(
  () => Boolean(conversationDisplayId.value) && !props.standalone
);
</script>

<template>
  <div
    class="group/card relative w-full shrink-0 overflow-hidden rounded-xl border border-n-weak bg-n-surface-1 py-3 ps-4 pe-3 text-start shadow-sm transition-colors hover:border-n-slate-7"
  >
    <!-- Stage accent rail (inline :style per repo precedent; slate fallback,
         dark ring guards pale colors on dark surfaces) -->
    <span
      class="absolute inset-y-0 start-0 w-[0.188rem] rounded-s-xl ring-1 ring-inset ring-n-alpha-1 dark:ring-n-alpha-2"
      :style="railStyle"
    />

    <!-- Primary action (open card details): a stretched, visually transparent
         button carrying the keyboard/screen-reader affordance and the full-card
         focus ring. The content layer sits above it (z-10) with pointer events
         enabled so inner tooltips/hover stay intact; content mouse-clicks open
         the drawer via their own @click, so pointer and keyboard reach the same
         action. The last-message bubble stops propagation to branch off. -->
    <button
      type="button"
      class="absolute inset-0 z-0 cursor-pointer rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      tabindex="-1"
      aria-hidden="true"
      @click="$emit('open', card)"
    />

    <div class="relative z-10 cursor-pointer" @click="$emit('open', card)">
      <div class="relative">
        <button
          type="button"
          class="min-h-11 w-full min-w-0 rounded px-0 py-1 text-start focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-n-brand"
          :aria-label="
            t('CRM_KANBAN.CARD.OPEN_DETAILS', { name: identityAriaName })
          "
          @click.stop="$emit('open', card)"
        >
          <span class="flex min-w-0 items-start gap-1.5" data-crm-card-identity>
            <span
              :class="identityIcon"
              class="mt-0.5 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            <span
              class="min-w-0 line-clamp-2 break-words text-base font-semibold leading-6 text-n-slate-12"
              :data-crm-card-company="companyName || undefined"
              :title="identityMain"
            >
              {{ identityMain }}
            </span>
          </span>
          <span
            v-if="identityPerson"
            class="ms-6 mt-0.5 block truncate text-sm font-normal leading-5 text-n-slate-11"
            :title="identityPerson"
            data-crm-card-person
          >
            {{ identityPerson }}
          </span>
          <span
            v-if="identityBusiness"
            class="ms-6 mt-1 block truncate text-xs font-normal leading-5 text-n-slate-11"
            :title="identityBusiness"
            data-crm-card-business
          >
            <span class="font-medium text-n-slate-10">
              {{ t('CRM_KANBAN.CARD.BUSINESS_LABEL') }}
            </span>
            {{ identityBusiness }}
          </span>
          <span
            v-if="!hasContact"
            class="ms-6 mt-1 block text-xs font-normal leading-5 text-n-slate-11"
            data-crm-card-no-contact
          >
            {{ t('CRM_KANBAN.DRAWER.NO_CONTACT') }}
          </span>
        </button>
      </div>

      <p
        v-if="card.description"
        class="mb-0 mt-2 line-clamp-2 text-xs leading-5 text-n-slate-11"
      >
        {{ card.description }}
      </p>

      <!-- Etiquetas (conversa primária + contato/campanha, deduplicadas) — mesma
           linha de labels da lista de Conversas, cor resolvida via store -->
      <CardLabels
        v-if="mergedLabels.length"
        class="mt-2"
        :conversation-labels="mergedLabels"
        :account-labels="accountLabels"
      />

      <!-- Origem da campanha — linha própria, separada das signal pills -->
      <div v-if="campaignPill" class="mt-2 flex items-center">
        <CrmCardPill
          :icon="campaignPill.icon"
          tone="teal"
          :title="formatOriginTitle(campaignPill)"
        >
          {{ humanizedOriginLabel(campaignPill) }}
          <template v-if="campaignPill.extraCount > 0" #trail>
            <span class="shrink-0 font-semibold">
              {{ `+${campaignPill.extraCount}` }}
            </span>
          </template>
        </CrmCardPill>
      </div>

      <!-- Primary signal row: value and attention stay together so the first
           glance answers what is being negotiated and what needs attention. -->
      <div
        v-if="valueLabel || scoreView || followUp || showPriorityGlyph"
        class="mt-3 flex flex-wrap items-center justify-between gap-2"
      >
        <span
          v-if="valueLabel"
          class="text-base font-semibold tabular-nums text-n-slate-12"
        >
          {{ valueLabel }}
        </span>

        <div class="flex min-w-0 flex-wrap items-center gap-1.5">
          <CardPriorityIcon
            v-if="showPriorityGlyph"
            :priority="card.priority"
            class="shrink-0"
          />
          <button
            v-if="scoreView"
            v-tooltip.top="
              scoreView.reason
                ? {
                    content: scoreView.reason,
                    delay: { show: 300, hide: 0 },
                  }
                : null
            "
            type="button"
            :aria-label="scoreView.ariaLabel"
            class="inline-flex max-w-full shrink-0 items-center gap-1 rounded-md px-2 py-1 text-xs font-medium leading-4 tabular-nums"
            :class="scoreView.toneClasses"
          >
            <span :class="scoreView.icon" class="size-3 shrink-0" />
            <span class="truncate">{{ scoreView.label }}</span>
          </button>
          <CrmCardPill
            v-if="followUp"
            :icon="followUp.icon"
            :tone="followUp.tone"
            :title="followUp.title"
          >
            {{ t('CRM_KANBAN.CARD.FOLLOW_UP_DUE', { time: followUp.label }) }}
          </CrmCardPill>
        </div>
      </div>

      <!-- Secondary signals stay available without competing with identity. -->
      <div
        v-if="
          slaChat ||
          handoffInvite ||
          card.inbox?.channel_type ||
          aiSuggestionLabel
        "
        class="mt-2.5 flex flex-wrap items-center gap-1.5"
      >
        <SLACardLabel v-if="slaChat" :chat="slaChat" />

        <CrmCardPill
          v-if="handoffInvite"
          icon="i-lucide-alarm-clock"
          :tone="handoffInvite.tone"
          :title="handoffInvite.title"
        >
          {{ handoffInvite.label }}
        </CrmCardPill>

        <CrmCardPill v-if="card.inbox?.channel_type" tone="default">
          <template #lead>
            <ChannelIcon
              :inbox="{ channel_type: card.inbox.channel_type }"
              class="size-3 shrink-0"
            />
          </template>
          {{ card.inbox.name }}
        </CrmCardPill>

        <CrmCardPill
          v-if="aiSuggestionLabel"
          icon="i-lucide-sparkles"
          tone="blue"
        >
          {{ aiSuggestionLabel }}
        </CrmCardPill>
      </div>

      <div
        class="mt-3 flex items-center justify-between gap-3 border-t border-n-weak pt-2.5 text-xs text-n-slate-11"
      >
        <span class="flex min-w-0 items-center gap-1" :title="responsibleLabel">
          <span :class="responsibleIcon" class="size-3 shrink-0" />
          <span class="truncate">{{ responsibleLabel }}</span>
        </span>
        <button
          v-if="lastMessageLabel && canOpenConversation"
          type="button"
          class="crm-card-open-conversation -my-1 -me-1 flex min-w-0 max-w-[45%] cursor-pointer items-center gap-1 rounded px-1 py-1 text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-brand hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-n-brand"
          :title="t('CRM_KANBAN.CARD.OPEN_CONVERSATION')"
          :aria-label="t('CRM_KANBAN.CARD.OPEN_CONVERSATION')"
          @click.stop="$emit('openConversation', card)"
        >
          <span class="i-lucide-message-circle size-3 shrink-0" />
          <span class="truncate">{{ lastMessageLabel }}</span>
        </button>
        <span
          v-else-if="lastMessageLabel && !standalone"
          class="flex min-w-0 max-w-[45%] items-center gap-1"
          :title="lastMessageTitle"
        >
          <span class="i-lucide-message-circle size-3 shrink-0" />
          <span class="truncate">{{ lastMessageLabel }}</span>
        </span>
      </div>
    </div>
  </div>
</template>
