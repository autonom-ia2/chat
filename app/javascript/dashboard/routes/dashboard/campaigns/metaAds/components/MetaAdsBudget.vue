<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  CENTS,
  META_DAY_FACTOR,
  ROLLING_DAYS,
  WEEK_DAYS,
  amountCents,
  centsToAmount,
  daysBetween,
  longDate,
  money,
  decimalAmount,
  todayOfAccount,
  withWords,
} from '../dinheiroDoAnuncio';
import { mudarOrcamento } from '../criacaoNaMeta';
import CampoDeValor from './CampoDeValor.vue';
import MetaAdsEndDate from './MetaAdsEndDate.vue';

// Anúncios da Meta (#2198): quanto o anúncio pode gastar e até quando, com o botão para mudar. O dinheiro mora no
// grupo de anúncios (o "conjunto" da Meta) ou na campanha, e é dividido entre os anúncios dele: a tela diz isso sem
// jargão. Mexe no dinheiro do cliente: a pessoa confere antes e depois, por extenso, antes de mudar; acima do teto,
// só pelo Gerenciador de Anúncios. Cada mudança fica na Auditoria da conta. Data de fim que já existe só troca: tirar o
// fim ainda não é aceito pelo servidor (`cannot_clear_end`), até a chamada real confirmar como a Meta aceita.
const props = defineProps({
  adId: { type: String, required: true },
  budget: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['changed']);

const { t, locale } = useI18n();

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.BUDGET';
// Mudar mais que 20% de uma vez faz a Meta testar de novo para quem mostrar.
const BIG_CHANGE = 0.2;

const dialog = ref(null);
const stage = ref('edit');
const saving = ref(false);
const amountText = ref('');
const endDate = ref('');

const currency = computed(() => props.budget.currency);
// Hoje no fuso da conta de anúncios, como o servidor conta.
const today = computed(() => todayOfAccount(props.budget.today));
// As contas são em centavos inteiros; estes dois recebem centavos e só convertem para mostrar.
const fmt = cents => money(centsToAmount(cents), currency.value, locale.value);
const spelled = cents =>
  withWords(centsToAmount(cents), currency.value, locale.value);
const currentCents = computed(
  () => props.budget.amount_cents ?? amountCents(props.budget.amount)
);
const minCents = computed(() => props.budget.min_daily * CENTS);
const maxCents = computed(() => props.budget.max_daily * CENTS);

const daily = computed(() => props.budget.kind === 'daily');
const oldEnd = computed(() => props.budget.end_time?.slice(0, 10) || '');

const amountLine = computed(() =>
  t(`${KEY}.${daily.value ? 'PER_DAY' : 'TOTAL'}`, {
    value: fmt(currentCents.value),
  })
);

const datesLine = computed(() => {
  const start = longDate(props.budget.start_time, locale.value);
  return oldEnd.value
    ? t(`${KEY}.DATES`, { start, end: longDate(oldEnd.value, locale.value) })
    : t(`${KEY}.DATES_NO_END`, { start });
});

const scopeLine = computed(() =>
  t(
    `${KEY}.SCOPE_${props.budget.level.toUpperCase()}`,
    { name: props.budget.object_name, count: props.budget.ads_count },
    props.budget.ads_count
  )
);

const showButton = computed(() => props.canManage && props.budget.can_change);

const newCents = computed(() => amountCents(amountText.value));

// Total: de R$ 6 até R$ 500 por dia de veiculação que falta (de hoje, ou do começo se ainda não começou, até o fim),
// a mesma conta do servidor.
const totalMax = computed(() => {
  if (daily.value || !endDate.value) return null;
  const start = props.budget.start_time?.slice(0, 10);
  const from = start && start > today.value ? start : today.value;
  return maxCents.value * Math.max(daysBetween(from, endDate.value), 1);
});

const totalError = cents => {
  if (cents < minCents.value) {
    return t(`${KEY}.ERRORS.TOTAL_MIN`, { value: fmt(minCents.value) });
  }
  if (totalMax.value != null && cents > totalMax.value) {
    return t(`${KEY}.ERRORS.TOTAL_MAX`, {
      value: fmt(totalMax.value),
      daily: fmt(maxCents.value),
    });
  }
  return null;
};

const amountError = computed(() => {
  const cents = newCents.value;
  if (cents == null) return t(`${KEY}.ERRORS.AMOUNT`);
  if (!daily.value) return totalError(cents);
  if (cents < minCents.value) {
    return t(`${KEY}.ERRORS.MIN`, { value: fmt(minCents.value) });
  }
  if (cents > maxCents.value) {
    return t(`${KEY}.ERRORS.MAX`, { value: fmt(maxCents.value) });
  }
  return null;
});

const dateError = computed(() =>
  !daily.value && !endDate.value ? t(`${KEY}.ERRORS.END_REQUIRED`) : null
);

const bigChange = computed(
  () =>
    newCents.value != null &&
    !amountError.value &&
    Math.abs(newCents.value - currentCents.value) / currentCents.value >
      BIG_CHANGE
);

const amountChanged = computed(() => newCents.value !== currentCents.value);
const endChanged = computed(() => endDate.value !== oldEnd.value);

const canReview = computed(
  () =>
    !amountError.value &&
    !dateError.value &&
    (amountChanged.value || endChanged.value)
);

const unit = computed(() => (daily.value ? 'PER_DAY' : 'TOTAL'));

const changes = computed(() => {
  const list = [];
  if (amountChanged.value) {
    list.push({
      key: 'AMOUNT',
      from: t(`${KEY}.${unit.value}`, { value: spelled(currentCents.value) }),
      to: t(`${KEY}.${unit.value}`, { value: spelled(newCents.value) }),
    });
  }
  if (endChanged.value) {
    list.push({
      key: 'END',
      from: longDate(oldEnd.value, locale.value) || t(`${KEY}.NO_END`),
      to: longDate(endDate.value, locale.value) || t(`${KEY}.NO_END`),
    });
  }
  return list;
});

// Com data para terminar: o total até lá. Sem data: o que gasta a cada 30 dias, deixando claro que continua.
const projection = computed(() => {
  if (!daily.value) return null;
  const cents = newCents.value;
  if (!endDate.value) {
    return t(`${KEY}.PROJECTION_NO_END`, {
      value: spelled(cents * ROLLING_DAYS),
    });
  }
  const days = daysBetween(today.value, endDate.value);
  return t(`${KEY}.PROJECTION_UNTIL`, {
    end: longDate(endDate.value, locale.value),
    days,
    value: spelled(cents * days),
  });
});

const dayLimits = computed(() =>
  daily.value
    ? t(`${KEY}.DAY_LIMITS`, {
        day: spelled(Math.round(newCents.value * META_DAY_FACTOR)),
        week: spelled(newCents.value * WEEK_DAYS),
      })
    : null
);

// O valor atual no campo como a pessoa escreveria: "30,00" em português, "30.00" em inglês.
const editableAmount = cents =>
  new Intl.NumberFormat(locale.value.startsWith('pt') ? 'pt-BR' : 'en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    useGrouping: false,
  }).format(centsToAmount(cents));

const open = () => {
  stage.value = 'edit';
  amountText.value = editableAmount(currentCents.value);
  endDate.value = oldEnd.value;
  dialog.value?.open();
};

// Recusas que a tela sabe explicar; outra vira a frase geral.
const FAILURES = [
  'invalid_amount',
  'invalid_dates',
  'cannot_clear_end',
  'meta_partial',
];
const failureMessage = error => {
  const code = error?.response?.data?.error;
  return FAILURES.includes(code)
    ? t(`${KEY}.FAILURES.${code.toUpperCase()}`)
    : t(`${KEY}.ERROR`);
};

const confirm = async () => {
  if (stage.value === 'edit') {
    if (canReview.value) stage.value = 'review';
    return;
  }
  saving.value = true;
  try {
    const data = await mudarOrcamento(props.adId, {
      // Texto decimal ("45.50"), do jeito que a pessoa digitou, sem passar por float.
      amount: decimalAmount(amountText.value),
      end_time: endDate.value ? `${endDate.value}T23:59:00` : null,
    });
    emit('changed', data);
    dialog.value?.close();
    useAlert(t(`${KEY}.DONE`));
  } catch (error) {
    useAlert(failureMessage(error));
  } finally {
    saving.value = false;
  }
};

const dialogTitle = computed(() =>
  t(`${KEY}.${stage.value === 'edit' ? 'EDIT_TITLE' : 'REVIEW_TITLE'}`)
);

const confirmLabel = computed(() => {
  if (stage.value === 'edit') return t(`${KEY}.REVIEW`);
  if (!amountChanged.value) return t(`${KEY}.CONFIRM_END`);
  return t(`${KEY}.CONFIRM_${unit.value}`, { value: fmt(newCents.value) });
});
</script>

<template>
  <section
    data-ad-budget
    class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-col gap-0.5">
      <h4 class="m-0 text-sm font-semibold text-n-slate-11">
        {{ $t(`${KEY}.TITLE`) }}
      </h4>
      <p class="m-0 text-xs text-n-slate-10">{{ scopeLine }}</p>
    </div>
    <div class="flex flex-col gap-1">
      <p
        data-ad-budget-amount
        class="m-0 text-2xl font-semibold tabular-nums text-n-slate-12"
      >
        {{ amountLine }}
      </p>
      <p data-ad-budget-dates class="m-0 text-sm text-n-slate-11">
        <span
          class="i-lucide-calendar size-4 align-[-3px]"
          aria-hidden="true"
        />
        {{ datesLine }}
      </p>
    </div>
    <button
      v-if="showButton"
      type="button"
      data-ad-budget-edit
      class="inline-flex min-h-11 items-center gap-2 self-start rounded-xl border-0 bg-transparent px-4 text-sm font-520 text-n-blue-11 ring-1 ring-inset ring-n-strong hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="open"
    >
      <span class="i-lucide-pencil size-4" aria-hidden="true" />
      {{ $t(`${KEY}.EDIT`) }}
    </button>

    <Dialog
      ref="dialog"
      :confirm-button-label="confirmLabel"
      :cancel-button-label="$t(`${KEY}.CANCEL`)"
      :disable-confirm-button="stage === 'edit' && !canReview"
      :is-loading="saving"
      overflow-y-auto
      @confirm="confirm"
    >
      <!-- O título fica no topo mesmo com o calendário aberto e o modal rolado (no celular ele passa da tela). -->
      <h3
        data-ad-budget-title
        class="sticky top-0 z-10 -mx-6 -mb-3 -mt-6 rounded-t-xl bg-n-solid-1 px-6 pb-3 pt-6 text-base font-medium leading-6 text-n-slate-12"
      >
        {{ dialogTitle }}
      </h3>
      <div
        v-if="stage === 'edit'"
        data-ad-budget-form
        class="flex min-w-0 flex-col gap-5"
      >
        <p class="m-0 text-sm text-n-slate-11">{{ scopeLine }}</p>
        <CampoDeValor
          v-model="amountText"
          data-ad-budget-input
          :currency="budget.currency"
          :error="Boolean(amountError)"
          :label="$t(`${KEY}.${daily ? 'AMOUNT_DAILY' : 'AMOUNT_TOTAL'}`)"
          :message="
            amountError ||
            (daily
              ? $t(`${KEY}.LIMITS`, {
                  min: fmt(minCents),
                  max: fmt(maxCents),
                })
              : '')
          "
        />
        <p
          v-if="bigChange"
          data-ad-budget-big
          class="m-0 flex gap-2 rounded-xl bg-n-amber-2 p-3 text-sm text-n-amber-12"
        >
          <span
            class="i-lucide-info mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ $t(`${KEY}.BIG_CHANGE`) }}
        </p>
        <MetaAdsEndDate
          v-model="endDate"
          :from="today"
          :allow-no-end="daily && !oldEnd"
        />
      </div>

      <div v-else data-ad-budget-review class="flex min-w-0 flex-col gap-4">
        <dl class="m-0 flex flex-col gap-3">
          <div
            v-for="change in changes"
            :key="change.key"
            :data-ad-budget-change="change.key"
            class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4"
          >
            <dt class="text-xs font-semibold text-n-slate-11">
              {{ $t(`${KEY}.CHANGE.${change.key}`) }}
            </dt>
            <dd class="m-0 text-sm text-n-slate-11">
              {{ $t(`${KEY}.FROM`) }}
              <span class="text-n-slate-12">{{ change.from }}</span>
            </dd>
            <dd class="m-0 text-base font-semibold text-n-slate-12">
              {{ $t(`${KEY}.TO`) }} {{ change.to }}
            </dd>
          </div>
        </dl>
        <p
          v-if="projection"
          data-ad-budget-projection
          class="m-0 text-sm text-n-slate-12"
        >
          {{ projection }}
        </p>
        <p v-if="dayLimits" class="m-0 text-sm text-n-slate-11">
          {{ dayLimits }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">{{ scopeLine }}</p>
        <button
          type="button"
          data-ad-budget-back
          class="inline-flex min-h-11 items-center gap-1.5 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="stage = 'edit'"
        >
          <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
          {{ $t(`${KEY}.BACK`) }}
        </button>
        <p class="m-0 flex gap-2 text-xs text-n-slate-10">
          <span
            class="i-lucide-shield-check mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ $t(`${KEY}.AUDIT`) }}
        </p>
      </div>
      <!-- O botão diz o valor ("Mudar para R$ 45,00 por dia"): no celular, um embaixo do outro para não cortar. -->
      <template #footer>
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
            data-ad-budget-confirm
            :label="confirmLabel"
            class="w-full sm:flex-1"
            :is-loading="saving"
            :disabled="(stage === 'edit' && !canReview) || saving"
            type="submit"
          />
        </div>
      </template>
    </Dialog>
  </section>
</template>
