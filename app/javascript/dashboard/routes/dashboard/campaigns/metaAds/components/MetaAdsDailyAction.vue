<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { formatFact } from '../metaAdsHelpers';

// "O que fazer hoje" (#1110, F5, §5.1): até 3 ações do consultor, decididas pelo servidor (Advisor::Decision) e
// na ordem dele. A tela não escolhe nada: mostra o texto da IA quando há, senão o da regra com os fatos de cada
// ação. O botão principal leva ao trabalho e grava a abertura; "Feito" é o aceite e "Dispensar" tira a ação do
// dia (D5.9). A ação aceita fica, marcada "Feita" (D5.10). Pedir a IA só quando o run está `pending`.
const props = defineProps({
  // panel.advice: { run_id, writer: { status, reason }, actions: [AdviceAction] }.
  advice: { type: Object, required: true },
  days: { type: Number, required: true },
  // A moeda da conta, para os fatos em dinheiro do texto da regra.
  currency: { type: String, default: 'BRL' },
  // Os alvos cuja lista está aberta no painel ('stalled_list', 'slow_replies'), para o aria-expanded.
  expanded: { type: Array, default: () => [] },
});

const emit = defineEmits(['act', 'changed']);

const { t, locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.PANEL.ACTION';
// Os estados em que o servidor já não escreve mais: o painel vale mais que a resposta guardada.
const FINAL = ['written', 'rule'];
const TOGGLES = ['stalled_list', 'slow_replies'];
const NAVIGATES = ['stalled_list', 'slow_replies', 'connection_step'];
// O número que escolhe singular ou plural no texto da regra de cada tipo.
const PLURAL_BY = {
  stalled_quotes: 'count',
  fix_tracking: 'unknown',
  slow_response: 'unanswered',
};

const answer = ref(null);
const asking = ref(false);
const failed = ref(false);
// O que a pessoa fez nesta tela, por id, até o próximo painel confirmar.
const accepted = ref([]);
const dismissed = ref([]);
const opened = ref([]);
const busy = ref([]);

const current = computed(() => {
  const fromPanel = props.advice;
  if (FINAL.includes(fromPanel.writer?.status)) return fromPanel;
  if (answer.value?.run_id === fromPanel.run_id) return answer.value;
  return fromPanel;
});

const actions = computed(() =>
  (current.value.actions || [])
    .filter(action => !action.id || !dismissed.value.includes(action.id))
    .map(action => ({
      ...action,
      status: accepted.value.includes(action.id) ? 'accepted' : action.status,
      opened: action.opened || opened.value.includes(action.id),
    }))
);

const fromAi = action => action.source === 'ai' && !!action.headline;
const anyAi = computed(() => actions.value.some(fromAi));
const writing = computed(
  () =>
    !anyAi.value && (asking.value || current.value.writer?.status === 'writing')
);

// Só quando a IA falhou: os outros motivos (sem IA, nada a dizer, teto do dia) ficam com a regra em silêncio.
const notice = computed(() => {
  if (failed.value) return t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.FAILED');
  if (current.value.writer?.reason === 'ai_error') {
    return t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.AI_ERROR');
  }
  return null;
});

// A resposta de outro run (o painel já mudou de análise) é descartada.
const ask = async () => {
  const runId = props.advice.run_id;
  asking.value = true;
  failed.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.dailyAction(props.days);
    if (data.daily_action?.run_id === props.advice.run_id) {
      answer.value = data.daily_action;
    }
  } catch {
    if (runId === props.advice.run_id) failed.value = true;
  } finally {
    asking.value = false;
  }
};

watch(
  () => props.advice,
  advice => {
    if (advice.writer?.status !== 'pending') {
      failed.value = false;
      return;
    }
    if (!asking.value) ask();
  },
  { immediate: true }
);

// "median_seconds" vira "medianSeconds" no texto; "ad" e "missing" são os nomes curtos dos textos da F3.
const paramName = key =>
  key
    .split('_')
    .map((part, index) =>
      index ? part.charAt(0).toUpperCase() + part.slice(1) : part
    )
    .join('');

const ruleParams = action => {
  const facts = action.facts || {};
  const formatted = Object.fromEntries(
    Object.entries(facts).map(([key, raw]) => [
      paramName(key),
      formatFact(key, raw, {
        t,
        currency: props.currency,
        locale: locale.value,
      }) ?? '',
    ])
  );
  return {
    ...formatted,
    ad:
      facts.ad_name ||
      action.ad_name ||
      t('CRM_KANBAN.META_ADS_HUB.PANEL.SEVERAL_ADS'),
    missing: formatted.missingConversations,
  };
};

const pluralOf = action => {
  const raw = action.facts?.[PLURAL_BY[action.kind]];
  return raw === null || raw === undefined ? 2 : Number(raw);
};

const ruleText = action => {
  const base = `${KEY}.${action.kind.toUpperCase()}`;
  const suffix = action.variant ? `_${action.variant.toUpperCase()}` : '';
  const params = ruleParams(action);
  const noMedian =
    action.kind === 'slow_response' && action.facts?.median_seconds == null;
  const textKey = noMedian
    ? `${base}.TEXT_UNANSWERED`
    : `${base}.TEXT${suffix}`;
  return {
    headline: t(textKey, params, pluralOf(action)),
    body: null,
    why: t(`${base}.WHY${suffix}`, params),
  };
};

const textOf = action =>
  fromAi(action)
    ? { headline: action.headline, body: action.body, why: action.why }
    : ruleText(action);

const items = computed(() =>
  actions.value.map(action => ({ ...action, text: textOf(action) }))
);

const targetOf = action => action.button?.target || 'none';

const hasButton = action => {
  const target = targetOf(action);
  if (target === 'acknowledge') return !!action.id && action.status === 'open';
  if (target === 'ads_manager') return !!action.button.url;
  if (target === 'ad_detail') return !!action.ad_id;
  return NAVIGATES.includes(target);
};

const buttonLabel = action =>
  t(
    `${KEY}.${action.kind.toUpperCase()}.BUTTON`,
    { count: action.facts?.count },
    pluralOf(action)
  );

const isExpanded = action =>
  TOGGLES.includes(targetOf(action))
    ? String(props.expanded.includes(targetOf(action)))
    : undefined;

// Gesto em andamento por id: dois cliques seguidos não mandam dois pedidos.
const run = async (action, request, onDone, failedKey) => {
  if (busy.value.includes(action.id)) return;
  busy.value = [...busy.value, action.id];
  try {
    await request(action.id);
    onDone();
  } catch {
    useAlert(t(`CRM_KANBAN.META_ADS_HUB.AI.DAILY.${failedKey}`));
  } finally {
    busy.value = busy.value.filter(id => id !== action.id);
  }
};

const accept = action =>
  run(
    action,
    CrmMetaAdsConnectionAPI.acceptAdvice,
    () => {
      accepted.value = [...accepted.value, action.id];
    },
    'DONE_FAILED'
  );

// A vaga da dispensada vai para a próxima candidata: o painel pede a análise de novo.
const dismiss = action =>
  run(
    action,
    CrmMetaAdsConnectionAPI.dismissAdvice,
    () => {
      dismissed.value = [...dismissed.value, action.id];
      emit('changed');
    },
    'DISMISS_FAILED'
  );

// A abertura só registra; a falha não segura a pessoa, vai para o console.
const markOpened = async action => {
  if (!action.id || action.opened) return;
  opened.value = [...opened.value, action.id];
  try {
    await CrmMetaAdsConnectionAPI.openAdvice(action.id);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[meta-ads] openAdvice failed', error?.constructor?.name);
  }
};

const go = action => {
  if (targetOf(action) === 'acknowledge') {
    accept(action);
    return;
  }
  emit('act', action);
  markOpened(action);
};

const canResolve = action => !!action.id && action.status === 'open';

const MAIN_BUTTON =
  'inline-flex items-center justify-center gap-1.5 px-4 text-sm font-520 no-underline rounded-lg min-h-11 whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white';
const mainClass = index =>
  index
    ? `${MAIN_BUTTON} bg-transparent border border-solid border-white/40 text-white hover:bg-white/10`
    : `${MAIN_BUTTON} bg-white border-0 text-[#0D2344] hover:bg-n-blue-2`;
const LINK_BUTTON =
  'p-0 text-[13px] font-460 bg-transparent border-0 rounded min-h-11 text-white/70 hover:text-white hover:underline disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white';
</script>

<template>
  <div
    data-panel-today
    class="relative flex flex-col gap-4 p-4 rounded-lg sm:p-5 bg-white/[0.07] ring-1 ring-inset ring-white/10"
  >
    <p
      class="flex flex-wrap items-center m-0 gap-x-2 gap-y-1 text-[11px] font-520 uppercase tracking-[0.1em] text-white/60"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.TODAY') }}
      <span
        v-if="anyAi"
        data-daily-ai-badge
        class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded normal-case tracking-normal bg-white/10 text-white/80"
      >
        <span class="i-lucide-sparkles size-3" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.BADGE') }}
      </span>
      <span
        v-else-if="writing"
        data-daily-writing
        class="inline-flex items-center gap-1 normal-case tracking-normal text-white/60"
      >
        <span
          class="i-lucide-loader-circle size-3 animate-spin"
          aria-hidden="true"
        />
        {{ $t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.WRITING') }}
      </span>
    </p>

    <ol
      data-panel-actions
      aria-live="polite"
      class="flex flex-col p-0 m-0 list-none"
    >
      <li
        v-for="(action, index) in items"
        :key="action.id ?? action.kind"
        data-panel-action
        :data-action-kind="action.kind"
        :data-action-source="fromAi(action) ? 'ai' : 'rule'"
        :data-action-id="action.id"
        :data-action-status="action.status"
        class="flex flex-col gap-3 sm:flex-row sm:items-start sm:gap-6"
        :class="
          index
            ? 'pt-4 mt-4 border-0 border-t border-solid border-white/10'
            : ''
        "
      >
        <div class="flex flex-1 min-w-0 gap-3">
          <span
            v-if="index"
            aria-hidden="true"
            class="grid flex-none mt-0.5 text-xs rounded-full size-6 place-items-center font-520 tabular-nums bg-white/10 text-white/80"
          >
            {{ index + 1 }}
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <span
              v-if="action.status === 'accepted'"
              data-action-done
              class="inline-flex items-center self-start gap-1 px-1.5 py-0.5 text-[11px] font-520 rounded bg-n-teal-9 text-white"
            >
              <span class="i-lucide-check size-3" aria-hidden="true" />
              {{ $t(`${KEY}.DONE_LABEL`) }}
            </span>
            <span
              data-daily-text
              class="block leading-snug text-pretty"
              :class="[
                index
                  ? 'text-[15px] font-460'
                  : 'text-[17px] sm:text-[19px] font-520',
                action.status === 'accepted' ? 'text-white/70' : 'text-white',
              ]"
            >
              {{ action.text.headline }}
            </span>
            <span
              v-if="!index && action.text.body"
              data-daily-body
              class="block text-sm leading-relaxed font-420 text-white/80"
            >
              {{ action.text.body }}
            </span>
            <p
              v-if="action.text.why"
              data-daily-why
              class="max-w-3xl m-0 text-[13px] font-420 leading-relaxed text-pretty text-white/65"
            >
              <span
                v-if="fromAi(action)"
                data-daily-why-label
                class="font-520 text-white/80"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.WHY_LABEL') }}
              </span>
              {{ action.text.why }}
            </p>
          </div>
        </div>

        <div
          v-if="hasButton(action) || canResolve(action)"
          class="flex flex-wrap items-center gap-x-4 gap-y-1 sm:flex-col sm:items-stretch sm:flex-none"
          :class="{ 'ps-9 sm:ps-0': index }"
        >
          <a
            v-if="hasButton(action) && targetOf(action) === 'ads_manager'"
            data-panel-action-button
            :href="action.button.url"
            target="_blank"
            rel="noopener noreferrer"
            :class="mainClass(index)"
            @click="markOpened(action)"
          >
            {{ buttonLabel(action) }}
            <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
          </a>
          <button
            v-else-if="hasButton(action)"
            type="button"
            data-panel-action-button
            :aria-expanded="isExpanded(action)"
            :disabled="busy.includes(action.id)"
            :class="mainClass(index)"
            @click="go(action)"
          >
            {{ buttonLabel(action) }}
          </button>
          <div
            v-if="canResolve(action)"
            class="flex flex-wrap items-center gap-x-4 sm:justify-center"
          >
            <button
              v-if="targetOf(action) !== 'acknowledge'"
              type="button"
              data-action-accept
              :disabled="busy.includes(action.id)"
              :class="LINK_BUTTON"
              @click="accept(action)"
            >
              {{ $t(`${KEY}.DONE`) }}
            </button>
            <button
              type="button"
              data-action-dismiss
              :disabled="busy.includes(action.id)"
              :class="LINK_BUTTON"
              @click="dismiss(action)"
            >
              {{ $t(`${KEY}.DISMISS`) }}
            </button>
          </div>
        </div>
      </li>
    </ol>

    <p
      v-if="notice"
      data-daily-notice
      role="status"
      class="inline-flex items-center max-w-3xl gap-1.5 m-0 text-xs font-420 text-white/60"
    >
      <span class="i-lucide-info size-3.5 flex-none" aria-hidden="true" />
      {{ notice }}
    </p>
  </div>
</template>
