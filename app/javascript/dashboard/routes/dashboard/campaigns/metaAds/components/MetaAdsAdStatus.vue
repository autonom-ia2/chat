<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { mudarStatus } from '../gestaoDoAnuncio';
import {
  amountCents,
  centsToAmount,
  daysBetween,
  longDate,
  todayOfAccount,
  withWords,
} from '../dinheiroDoAnuncio';

// Anúncios da Meta (#2161): no topo do anúncio, se ele está no ar ou pausado e o botão para mudar. Pausar é sempre
// gesto da pessoa, com confirmação; o consultor só sugere. Quem não pode mexer (só vê, ou modo parceiro) vê a
// situação sem o botão. Token sem permissão de mudar: a frase diz como liberar, sem esconder.
const props = defineProps({
  adId: { type: String, required: true },
  adName: { type: String, default: '' },
  gestao: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  // Orçamento (#2198): com ele, ativar diz quanto vai gastar e até quando antes de o dinheiro começar a sair.
  budget: { type: Object, default: null },
  // Com a gestão de orçamento ligada ('loading' | 'failed' | 'ok'), ativar espera o orçamento: nunca ativa sem dizer
  // o valor. '' quando não há gestão de orçamento.
  budgetState: { type: String, default: '' },
  // Leitura no toque (lista de pausados, #2198): () => Promise<orçamento>. Com ela, o toque em "Ativar" lê o orçamento
  // de agora antes de abrir a confirmação, e `budget`/`budgetState` não valem: a frase usa só o que acabou de ler.
  readBudget: { type: Function, default: null },
  // 'dark' no topo escuro do anúncio; 'light' nas listas do painel.
  tone: { type: String, default: 'dark' },
});

const emit = defineEmits(['changed', 'retryBudget']);

const { t, locale } = useI18n();
const dialog = ref(null);
const saving = ref(false);

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS';
// Ativar um anúncio criado aqui liga campanha, grupo e anúncio (#2198); `meta_partial`: um falhou e nem voltar deu.
const STATUS_ERRORS = {
  cannot_change: 'NEEDS_LOGIN',
  meta_partial: 'PARTIAL',
  pause_partial: 'PAUSE_PARTIAL',
  in_progress: 'IN_PROGRESS',
  // A Meta ainda analisa o anúncio (#2354): ligar fica para quando ela terminar.
  in_review: 'IN_REVIEW',
};

// O botão mexe na situação do próprio anúncio. "No ar" só quando a entrega também está ativa: anúncio ativo com a
// campanha ou o conjunto pausado (ou em análise, recusado…) fica "Fora do ar", e pausar continua valendo.
const active = computed(() => props.gestao.status === 'ACTIVE');
// Arquivado ou apagado também é "Fora do ar" (e sem botão: só ACTIVE e PAUSED mudam por aqui).
const badge = computed(() => {
  if (props.gestao.status === 'PAUSED') return 'PAUSED';
  return active.value && props.gestao.effective_status === 'ACTIVE'
    ? 'ACTIVE'
    : 'OFF';
});
const action = computed(() => (active.value ? 'PAUSE' : 'ACTIVATE'));
// Pausado em análise da Meta (`in_review`, #2354): o servidor recusaria o ligar. No lugar do botão, a frase de que a
// Meta está conferindo. A mesma regra na lista de pausados, no topo do anúncio e no cartão de criado.
const inReview = computed(
  () => props.gestao.status === 'PAUSED' && Boolean(props.gestao.in_review)
);
const showButton = computed(
  () =>
    props.canManage &&
    props.gestao.can_change &&
    !inReview.value &&
    ['ACTIVE', 'PAUSED'].includes(props.gestao.status)
);
const showLoginHint = computed(
  () => props.canManage && props.gestao.needs_login
);

// Quanto vai gastar, por extenso, contando do dia em que começa (hoje ou o começo marcado, o mais tarde).
// Lido no toque (com `readBudget`) ou o que a tela já leu.
const tapBudget = ref(null);
const tapState = ref('');
const currentBudget = computed(() =>
  props.readBudget ? tapBudget.value : props.budget
);
const currentState = computed(() =>
  props.readBudget ? tapState.value : props.budgetState
);

const spend = computed(() => {
  const budget = currentBudget.value;
  if (action.value !== 'ACTIVATE' || !budget) return null;
  const fmt = value => withWords(value, budget.currency, locale.value);
  const end = budget.end_time?.slice(0, 10);
  if (budget.kind === 'lifetime') {
    return t(`${KEY}.ACTIVATE_SPEND_TOTAL`, {
      total: fmt(budget.amount),
      end: longDate(end, locale.value),
    });
  }
  // Grupo (ou campanha) com outros anúncios no ar: este passa a dividir o mesmo dinheiro, o gasto não aumenta. Com os
  // outros pausados, ele gasta sozinho, e vale o texto do diário.
  const others = budget.active_ads_count || 0;
  if (others > 0) {
    const shared =
      budget.level === 'campaign'
        ? 'ACTIVATE_SPEND_SHARED_CAMPAIGN'
        : 'ACTIVATE_SPEND_SHARED';
    return t(
      `${KEY}.${shared}`,
      { value: fmt(budget.amount), name: budget.object_name, others },
      others
    );
  }
  const value = fmt(budget.amount);
  if (!end) return t(`${KEY}.ACTIVATE_SPEND_NO_END`, { value });
  const start = budget.start_time?.slice(0, 10);
  const today = todayOfAccount(budget.today);
  const from = start && start > today ? start : today;
  return t(`${KEY}.ACTIVATE_SPEND_END`, {
    value,
    end: longDate(end, locale.value),
    total: fmt(
      centsToAmount(
        (budget.amount_cents ?? amountCents(budget.amount)) *
          daysBetween(from, end)
      )
    ),
  });
});

// Ativar sem o orçamento lido: o botão espera, em vez de cair no texto sem valor. Na falha, a frase diz e o botão
// "Tentar de novo" lê outra vez.
const blockedBy = computed(() =>
  action.value === 'ACTIVATE' &&
  ['loading', 'failed'].includes(currentState.value)
    ? currentState.value
    : ''
);

// Com leitura no toque, "Ativar" lê primeiro e só abre a confirmação com o orçamento de agora; na falha, não abre.
const openDialog = async () => {
  if (!props.readBudget || action.value !== 'ACTIVATE') {
    dialog.value?.open();
    return;
  }
  tapBudget.value = null;
  tapState.value = 'loading';
  try {
    const budget = await props.readBudget();
    if (!budget) throw new Error('budget_not_found');
    tapBudget.value = budget;
    tapState.value = '';
    dialog.value?.open();
  } catch {
    tapState.value = 'failed';
  }
};
const retryBudget = () => {
  if (props.readBudget) openDialog();
  else emit('retryBudget');
};

const light = computed(() => props.tone === 'light');
const BADGE_CLASSES = {
  dark: {
    ACTIVE: 'bg-n-teal-9/20 text-white',
    OTHER: 'bg-white/10 text-white/80',
  },
  light: {
    ACTIVE: 'bg-n-teal-3 text-n-teal-11',
    OTHER: 'bg-n-alpha-2 text-n-slate-11',
  },
};
const badgeClass = computed(
  () => BADGE_CLASSES[props.tone][badge.value === 'ACTIVE' ? 'ACTIVE' : 'OTHER']
);

// O botão principal do topo (Ativar/Pausar, ou "Tentar de novo" quando o orçamento não veio).
const primaryClass = computed(() =>
  light.value
    ? 'bg-n-brand text-white hover:bg-n-brand/90 focus-visible:ring-n-brand focus-visible:ring-offset-2'
    : 'bg-white text-n-heroi hover:bg-n-blue-2 focus-visible:ring-white'
);

const description = computed(
  () => spend.value || t(`${KEY}.${action.value}_HINT`)
);

// Ativado, mas a campanha ou o grupo seguem pausados no Gerenciador da Meta (`held_by`, #2198): avisa em vez de dizer
// que começou a rodar.
const HELD_BY = ['campaign', 'adset'];
const doneMessage = (done, result) => {
  const held = done === 'ACTIVATE' && result?.held_by;
  return HELD_BY.includes(held)
    ? t(`${KEY}.HELD.${held.toUpperCase()}`)
    : t(`${KEY}.${done}_DONE`);
};

const confirmLabel = computed(() =>
  spend.value ? t(`${KEY}.ACTIVATE_SPEND_BUTTON`) : t(`${KEY}.${action.value}`)
);

const confirm = async () => {
  saving.value = true;
  const done = action.value;
  const next = active.value ? 'PAUSED' : 'ACTIVE';
  try {
    const result = await mudarStatus(props.adId, next);
    emit('changed', next, result);
    dialog.value?.close();
    useAlert(doneMessage(done, result));
  } catch (error) {
    const code = error?.response?.data?.error;
    useAlert(t(`${KEY}.${STATUS_ERRORS[code] || 'ERROR'}`));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div
    data-ad-status
    :data-status="badge"
    class="relative flex flex-wrap items-center gap-3 pt-1"
  >
    <span
      data-ad-status-badge
      class="inline-flex min-h-8 items-center gap-2 rounded-full px-3 text-sm font-medium"
      :class="badgeClass"
    >
      <span
        class="size-2 rounded-full"
        :class="{
          'bg-n-teal-9': badge === 'ACTIVE',
          'bg-n-slate-9': badge !== 'ACTIVE' && light,
          'bg-white/50': badge !== 'ACTIVE' && !light,
        }"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.${badge}`) }}
    </span>
    <!-- Orçamento que não veio: o "Ativar" desligado sai, e o "Tentar de novo" ocupa o lugar dele. -->
    <button
      v-if="showButton && blockedBy !== 'failed'"
      type="button"
      data-ad-status-toggle
      :disabled="Boolean(blockedBy)"
      :aria-busy="blockedBy === 'loading' || undefined"
      class="inline-flex min-h-11 items-center gap-2 rounded-lg border-0 px-4 text-sm font-520 focus-visible:outline-none focus-visible:ring-2 disabled:cursor-wait disabled:opacity-60"
      :class="primaryClass"
      @click="openDialog"
    >
      <span
        :class="{
          'i-lucide-loader-circle animate-spin': blockedBy === 'loading',
          'i-lucide-pause': blockedBy !== 'loading' && active,
          'i-lucide-play': blockedBy !== 'loading' && !active,
        }"
        class="size-4"
        aria-hidden="true"
      />
      {{ $t(`${KEY}.${action}`) }}
    </button>
    <p
      v-if="showButton && blockedBy === 'loading'"
      data-ad-status-budget-pending
      role="status"
      class="m-0 text-sm"
      :class="light ? 'text-n-slate-11' : 'text-white/75'"
    >
      {{ $t(`${KEY}.BUDGET_PENDING`) }}
    </p>
    <template v-else-if="showButton && blockedBy === 'failed'">
      <button
        type="button"
        data-ad-status-budget-retry
        class="inline-flex min-h-11 items-center gap-2 rounded-lg border-0 px-4 text-sm font-520 focus-visible:outline-none focus-visible:ring-2"
        :class="primaryClass"
        @click="retryBudget"
      >
        <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
        {{ $t(`${KEY}.BUDGET_RETRY`) }}
      </button>
      <p
        data-ad-status-budget-failed
        role="alert"
        class="m-0 basis-full text-sm"
        :class="light ? 'text-n-ruby-11' : 'text-white'"
      >
        {{ $t(`${KEY}.BUDGET_FAILED`) }}
      </p>
    </template>
    <p
      v-else-if="inReview"
      data-ad-status-review
      role="status"
      class="m-0 flex max-w-sm gap-2 text-sm"
      :class="light ? 'text-n-slate-11' : 'text-white/75'"
    >
      <span
        class="i-lucide-hourglass mt-0.5 size-4 shrink-0"
        :class="light ? 'text-n-amber-11' : 'text-white'"
        aria-hidden="true"
      />
      <span>
        {{ $t(`${KEY}.IN_REVIEW_NOTE`) }}
        {{ $t(`${KEY}.IN_REVIEW_NOTE_HINT`) }}
      </span>
    </p>
    <p
      v-else-if="!showButton && showLoginHint"
      data-ad-status-login
      class="m-0 text-sm text-white/75"
    >
      {{ $t(`${KEY}.NEEDS_LOGIN`) }}
    </p>

    <Dialog
      ref="dialog"
      type="alert"
      :title="$t(`${KEY}.${action}_TITLE`, { name: adName })"
      :description="description"
      :confirm-button-label="confirmLabel"
      :cancel-button-label="$t(`${KEY}.CANCEL`)"
      :is-loading="saving"
      @confirm="confirm"
    >
      <!-- Botão com frase longa ("Ativar e começar a gastar"): no celular, um embaixo do outro para não cortar. Sem o
           valor, o rodapé de sempre do diálogo. -->
      <template v-if="spend" #footer>
        <div
          class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:items-center"
        >
          <Button
            variant="faded"
            color="slate"
            :label="$t(`${KEY}.CANCEL`)"
            class="w-full sm:flex-1"
            type="button"
            @click="dialog?.close()"
          />
          <Button
            data-ad-status-confirm
            color="ruby"
            :label="confirmLabel"
            class="w-full sm:flex-1"
            :is-loading="saving"
            :disabled="saving"
            type="submit"
          />
        </div>
      </template>
    </Dialog>
  </div>
</template>
