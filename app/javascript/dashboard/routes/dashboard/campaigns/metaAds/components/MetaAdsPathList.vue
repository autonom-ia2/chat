<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { amount, duration, relativeTime } from '../metaAdsHelpers';
import MetaAdsQuoteMessage from './MetaAdsQuoteMessage.vue';

// Uma etapa do caminho do dinheiro aberta dentro do painel (#1110, F5, §5.4, D5.7): as conversas, propostas ou
// vendas da mesma coorte do número clicado (Crm::MetaAds::Panel::PathList), ou as conversas mais demoradas de
// "O que fazer hoje". Cada linha leva à conversa e, com card, ao CRM (?card_id= abre a gaveta no funil certo).
// A proposta parada traz o "Sugerir mensagem" da F4, para a sugestão não sumir quando as paradas são dispensadas.
// O Kanban filtrado pela coorte fica fora desta fase (CA-3.2 parcial).
const props = defineProps({
  // 'conversations' | 'quotes' | 'sales' | 'slow_replies'
  step: { type: String, required: true },
  days: { type: Number, required: true },
  currency: { type: String, default: 'BRL' },
});

const { t, locale } = useI18n();
const route = useRoute();
const LIST = 'CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST';
const SLOW_AFTER_SECONDS = 300;

const list = ref(null);
const loading = ref(true);
const failed = ref(false);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.panelList(
      props.step,
      props.days
    );
    list.value = data.list;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const items = computed(() => list.value?.items || []);
const total = computed(() => list.value?.total || 0);
const stepKey = computed(() => props.step.toUpperCase());

const accountId = computed(() => route.params.accountId);
const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: accountId.value, id }));
const cardLink = cardId => ({
  name: 'crm_kanban_index',
  params: { accountId: accountId.value },
  query: { card_id: String(cardId) },
});

const fmt = value => amount(value, props.currency, locale.value);

// A espera da proposta ou o tempo de resposta da conversa: o que mais importa em cada etapa.
const timing = item => {
  if (props.step === 'slow_replies' || props.step === 'conversations') {
    if (item.answered === false) return { text: t(`${LIST}.NO_ANSWER`) };
    if (item.response_seconds == null) return null;
    return {
      text: t(`${LIST}.ANSWERED_IN`, {
        duration: duration(item.response_seconds, t),
      }),
      slow: item.response_seconds > SLOW_AFTER_SECONDS,
    };
  }
  if (item.status === 'open' && item.waiting_since) {
    return {
      text: t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_SINCE', {
        time: relativeTime(item.waiting_since, locale.value),
      }),
      slow: item.stalled,
    };
  }
  return null;
};

onMounted(load);
</script>

<template>
  <section
    data-panel-path-list
    :data-path-list-step="step"
    class="flex flex-col gap-4 pt-5 border-0 border-t border-solid border-n-weak"
  >
    <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
      <h5 class="m-0 text-sm font-520 text-n-slate-12">
        {{ $t(`${LIST}.TITLE_${stepKey}`) }}
        <span
          v-if="step === 'slow_replies'"
          data-path-list-period
          class="font-420 text-n-slate-11 before:content-['·'] before:mx-1"
        >
          {{ $t(`${LIST}.LAST_30_DAYS`) }}
        </span>
      </h5>
      <span
        v-if="list"
        data-path-list-total
        class="text-[13px] font-440 tabular-nums text-n-slate-11"
      >
        {{ $t(`${LIST}.TOTAL_${stepKey}`, { count: total }, total) }}
      </span>
    </div>

    <div v-if="loading" class="flex justify-center py-6">
      <Spinner />
    </div>

    <div
      v-else-if="failed"
      data-path-list-error
      role="alert"
      class="flex flex-wrap items-center gap-3"
    >
      <p class="m-0 text-sm font-420 text-n-slate-11">
        {{ $t(`${LIST}.ERROR`) }}
      </p>
      <button
        type="button"
        data-path-list-retry
        class="px-3 text-[13px] font-460 border border-solid rounded-lg min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="load"
      >
        {{ $t(`${LIST}.RETRY`) }}
      </button>
    </div>

    <p
      v-else-if="!items.length"
      data-path-list-empty
      class="m-0 text-sm font-420 text-n-slate-11"
    >
      {{ $t(`${LIST}.EMPTY`) }}
    </p>

    <template v-else>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="item in items"
          :key="`${item.conversation_id}-${item.card_id}`"
          data-panel-path-item
          :data-path-item-stalled="item.stalled || undefined"
          class="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 border border-solid rounded-lg border-n-weak"
        >
          <span class="flex flex-col flex-1 min-w-[12rem] gap-0.5">
            <span class="text-sm truncate font-520 text-n-slate-12">
              {{ item.title || $t(`${LIST}.NO_TITLE`) }}
            </span>
            <span
              class="flex flex-wrap text-xs gap-x-2 font-420 text-n-slate-10"
            >
              <span v-if="item.ad_name" class="truncate max-w-[16rem]">
                {{ item.ad_name }}
              </span>
              <span v-if="item.stage_name">{{ item.stage_name }}</span>
              <span
                v-if="item.status === 'won' || item.status === 'lost'"
                :class="
                  item.status === 'won' ? 'text-n-teal-11' : 'text-n-slate-11'
                "
              >
                {{ $t(`${LIST}.${item.status.toUpperCase()}`) }}
              </span>
              <span
                v-if="timing(item)"
                data-path-item-timing
                :class="{ 'text-n-amber-11': timing(item).slow }"
              >
                {{ timing(item).text }}
              </span>
            </span>
          </span>
          <span
            v-if="item.value != null"
            class="text-base font-interDisplay font-520 tabular-nums text-n-slate-12"
          >
            {{ fmt(item.value) }}
          </span>
          <span class="flex flex-wrap items-center gap-2">
            <router-link
              data-path-item-conversation
              :to="conversationLink(item.conversation_id)"
              class="inline-flex items-center px-3 text-[13px] font-460 no-underline border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            >
              {{ $t(`${LIST}.OPEN_CONVERSATION`) }}
            </router-link>
            <router-link
              v-if="item.card_id"
              data-path-item-card
              :to="cardLink(item.card_id)"
              class="inline-flex items-center px-3 text-[13px] font-460 no-underline border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            >
              {{ $t(`${LIST}.OPEN_CARD`) }}
            </router-link>
            <MetaAdsQuoteMessage
              v-if="step === 'quotes' && item.stalled && item.card_id"
              :card="{
                id: item.card_id,
                conversation_id: item.conversation_id,
              }"
            />
          </span>
        </li>
      </ul>
      <p
        v-if="total > items.length"
        data-path-list-showing
        class="m-0 text-[13px] font-420 text-n-slate-11"
      >
        {{ $t(`${LIST}.SHOWING`, { shown: items.length, total }) }}
      </p>
    </template>
  </section>
</template>
