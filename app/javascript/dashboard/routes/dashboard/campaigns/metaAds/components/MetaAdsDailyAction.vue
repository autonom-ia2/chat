<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// "O que fazer hoje" (#1100, F4a). A ação pela regra aparece na hora; a versão escrita pela IA chega depois e
// entra no lugar do texto. Os números continuam os da regra. Se a IA não responder, a regra fica, com o aviso.
const props = defineProps({
  // panel.action: a ação do dia pela regra (Crm::MetaAds::Panel::Action).
  action: { type: Object, required: true },
  // O texto da regra, já pronto no painel: { text, why }.
  ruleText: { type: Object, required: true },
  days: { type: Number, required: true },
});

const emit = defineEmits(['act']);

const { t } = useI18n();
const daily = ref(null);
const writing = ref(false);
const failed = ref(false);

const BUTTON_KINDS = ['stalled_quotes', 'fix_tracking', 'review_ad'];

// Troca de período no meio do pedido: a resposta do período antigo é descartada.
const ask = async () => {
  const asked = props.days;
  writing.value = true;
  failed.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.dailyAction(asked);
    if (asked !== props.days) return;
    daily.value = data.daily_action;
  } catch {
    if (asked !== props.days) return;
    daily.value = null;
    failed.value = true;
  } finally {
    if (asked === props.days) writing.value = false;
  }
};

const fromAi = computed(() => daily.value?.source === 'ai');
const kind = computed(() =>
  fromAi.value ? daily.value.kind : props.action.kind
);

const text = computed(() =>
  fromAi.value ? daily.value.headline : props.ruleText.text
);
const detail = computed(() => (fromAi.value ? daily.value.body : null));
const why = computed(() =>
  fromAi.value ? daily.value.why : props.ruleText.why
);

// Só quando a IA falhou: os outros motivos (sem IA, nada a dizer, teto do dia) ficam com a regra em silêncio.
const notice = computed(() => {
  if (failed.value) return t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.FAILED');
  if (daily.value?.reason === 'ai_error') {
    return t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.AI_ERROR');
  }
  return null;
});

const showButton = computed(
  () =>
    BUTTON_KINDS.includes(kind.value) &&
    (kind.value !== 'review_ad' || daily.value?.ad_id)
);
const buttonLabel = computed(() => {
  if (kind.value === 'review_ad') {
    return t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.REVIEW_AD_BUTTON');
  }
  return t(
    `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.${kind.value.toUpperCase()}.BUTTON`,
    { count: props.action.count },
    props.action.count ?? 2
  );
});

const act = () =>
  emit('act', {
    kind: kind.value,
    adId: fromAi.value ? daily.value.ad_id : null,
  });

// A regra achou propostas paradas, mas a IA escolheu outra ação: a lista (e a mensagem sugerida) continua a um
// clique, num botão secundário.
const showStalledButton = computed(
  () =>
    props.action.kind === 'stalled_quotes' && kind.value !== 'stalled_quotes'
);
const stalledLabel = computed(() =>
  t(
    'CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.STALLED_QUOTES.BUTTON',
    { count: props.action.count },
    props.action.count ?? 2
  )
);
const openStalled = () => emit('act', { kind: 'stalled_quotes', adId: null });

watch(
  () => [props.days, props.action.kind],
  () => ask()
);
onMounted(ask);
</script>

<template>
  <div class="relative flex flex-col gap-5">
    <div
      data-panel-action
      :data-action-kind="kind"
      :data-action-source="fromAi ? 'ai' : 'rule'"
      class="flex flex-col gap-4 p-4 rounded-lg sm:p-5 bg-white/[0.07] ring-1 ring-inset ring-white/10 sm:flex-row sm:items-center"
    >
      <div class="flex-1 m-0" aria-live="polite">
        <span
          class="flex flex-wrap items-center mb-1 gap-x-2 gap-y-1 text-[11px] font-520 uppercase tracking-[0.1em] text-white/60"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.TODAY') }}
          <span
            v-if="fromAi"
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
        </span>
        <span
          data-daily-text
          class="block text-[15px] font-440 leading-relaxed text-white"
        >
          {{ text }}
        </span>
        <span
          v-if="detail"
          data-daily-body
          class="block mt-1 text-sm font-420 leading-relaxed text-white/80"
        >
          {{ detail }}
        </span>
      </div>
      <div
        v-if="showButton || showStalledButton"
        class="flex flex-col gap-2 sm:items-stretch"
      >
        <button
          v-if="showButton"
          type="button"
          data-panel-action-button
          class="px-4 text-sm font-520 bg-white border-0 rounded-lg min-h-11 text-[#0D2344] whitespace-nowrap hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
          @click="act"
        >
          {{ buttonLabel }}
        </button>
        <button
          v-if="showStalledButton"
          type="button"
          data-panel-stalled-button
          class="px-4 text-sm font-520 bg-transparent border border-solid rounded-lg min-h-11 border-white/40 text-white whitespace-nowrap hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
          @click="openStalled"
        >
          {{ stalledLabel }}
        </button>
      </div>
    </div>
    <div class="flex flex-col gap-1.5">
      <p
        v-if="why"
        data-daily-why
        class="max-w-3xl m-0 text-[13px] font-420 leading-relaxed text-pretty text-white/65"
      >
        <span v-if="fromAi" data-daily-why-label class="font-520 text-white/80">
          {{ $t('CRM_KANBAN.META_ADS_HUB.AI.DAILY.WHY_LABEL') }}
        </span>
        {{ why }}
      </p>
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
  </div>
</template>
