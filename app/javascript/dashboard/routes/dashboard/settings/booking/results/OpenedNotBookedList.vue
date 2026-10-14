<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingStatsAPI from 'dashboard/api/crmBookingStats';
import { timeAgo } from './resultsFormat';

// "Abriram o link e não marcaram" (J7-A4, J8-A12): uma linha por cliente, só
// clientes que a pessoa pode ver. "Enviar de novo" manda o link na conversa do
// cliente, como a própria pessoa, só quando ela toca. A janela de mensagens
// fechada é recusada pelo servidor e explicada aqui.
const props = defineProps({
  period: { type: Number, required: true },
  scope: { type: String, required: true },
});

const emit = defineEmits(['changePeriod']);

const ERRORS = {
  'crm.booking_v2.cannot_reply': 'BOOKING.RESULTS.LIST.ERRORS.CANNOT_REPLY',
  'crm.booking_v2.no_conversation':
    'BOOKING.RESULTS.LIST.ERRORS.NO_CONVERSATION',
  'crm.booking_v2.no_page': 'BOOKING.RESULTS.LIST.ERRORS.NO_PAGE',
};
const HTTP_UNAUTHORIZED = 401;

const { t, locale } = useI18n();
const rows = ref([]);
const meta = ref({ page: 1, total: 0 });
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const sendingId = ref(null);
const notices = ref({});
const listRoot = ref(null);

// Só quem pode mandar o link vê "Enviar de novo" e a dica de quando não dá.
const canSend = computed(() => meta.value.can_resend !== false);
const hasMore = computed(() => rows.value.length < meta.value.total);
const hint = computed(() =>
  props.scope === 'mine'
    ? t('BOOKING.RESULTS.LIST.HINT_MINE')
    : t('BOOKING.RESULTS.LIST.HINT_TEAM')
);

const fetchPage = page =>
  BookingStatsAPI.openedNotBooked({
    period: props.period,
    scope: props.scope,
    page,
  });

const load = async () => {
  loading.value = true;
  failed.value = false;
  notices.value = {};
  try {
    const { data } = await fetchPage(1);
    rows.value = data.payload || [];
    meta.value = data.meta || { page: 1, total: rows.value.length };
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const loadMore = async () => {
  loadingMore.value = true;
  try {
    const { data } = await fetchPage(meta.value.page + 1);
    // Alguém pode ter aberto um link entre as páginas: a mesma linha não entra duas vezes.
    const seen = new Set(rows.value.map(item => item.id));
    const fresh = (data.payload || []).filter(item => !seen.has(item.id));
    rows.value = [...rows.value, ...fresh];
    meta.value = data.meta || meta.value;
  } catch {
    useAlert(t('BOOKING.RESULTS.LIST.ERROR'));
  } finally {
    loadingMore.value = false;
  }
};

const errorKey = error => {
  if (error?.response?.status === HTTP_UNAUTHORIZED) {
    return 'BOOKING.RESULTS.LIST.ERRORS.FORBIDDEN';
  }
  return (
    ERRORS[error?.response?.data?.error] ||
    'BOOKING.RESULTS.LIST.ERRORS.GENERIC'
  );
};

const resend = async row => {
  sendingId.value = row.id;
  notices.value = { ...notices.value, [row.id]: '' };
  try {
    const { data } = await BookingStatsAPI.resend(row.id);
    rows.value = rows.value.map(item =>
      item.id === row.id ? { ...item, resent_at: data.payload.resent_at } : item
    );
    useAlert(t('BOOKING.RESULTS.LIST.SENT_OK'));
    // O botão some: o foco vai para o "Enviado de novo" da mesma linha, sem se perder.
    await nextTick();
    listRoot.value
      ?.querySelector(`[data-row="${row.id}"] [data-resent]`)
      ?.focus();
  } catch (error) {
    notices.value = { ...notices.value, [row.id]: t(errorKey(error)) };
  } finally {
    sendingId.value = null;
  }
};

const emptyAction = () => {
  if (props.period < 30) {
    emit('changePeriod', 30);
    return;
  }
  load();
};

const openedText = row =>
  t('BOOKING.RESULTS.LIST.OPENED', {
    when: timeAgo(row.opened_at, locale.value),
  });

const viaText = row =>
  row.sent_by
    ? t('BOOKING.RESULTS.LIST.VIA', {
        page: row.page.title,
        name: row.sent_by.name,
      })
    : row.page.title;

watch(() => [props.period, props.scope], load, { immediate: true });
// Separador visual entre dois trechos já traduzidos (não é texto a traduzir).
const SEPARATOR = ' · ';
</script>

<template>
  <section
    ref="listRoot"
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    aria-labelledby="booking-results-list"
  >
    <header class="flex flex-col gap-1">
      <h2
        id="booking-results-list"
        class="m-0 text-base font-semibold text-n-slate-12"
      >
        {{ t('BOOKING.RESULTS.LIST.TITLE') }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">{{ hint }}</p>
    </header>

    <div
      v-if="loading"
      aria-busy="true"
      data-list-loading
      class="flex flex-col gap-2"
    >
      <span class="sr-only">{{ t('BOOKING.RESULTS.LIST.LOADING') }}</span>
      <div
        v-for="item in 3"
        :key="item"
        class="h-16 rounded-xl bg-n-alpha-2 animate-pulse"
      />
    </div>

    <div
      v-else-if="failed"
      role="alert"
      data-list-error
      class="flex flex-col items-start gap-3"
    >
      <p class="m-0 text-sm text-n-ruby-11">
        {{ t('BOOKING.RESULTS.LIST.ERROR') }}
      </p>
      <button
        type="button"
        class="min-h-11 px-4 rounded-xl text-sm font-semibold text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="load"
      >
        {{ t('BOOKING.RESULTS.RETRY') }}
      </button>
    </div>

    <div
      v-else-if="!rows.length"
      data-list-empty
      class="flex flex-col items-start gap-3"
    >
      <p class="m-0 text-sm text-n-slate-12">
        {{ t('BOOKING.RESULTS.LIST.EMPTY', { days: period }) }}
      </p>
      <button
        type="button"
        data-list-empty-action
        class="min-h-11 px-4 rounded-xl text-sm font-semibold text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emptyAction"
      >
        {{
          period < 30
            ? t('BOOKING.RESULTS.SEE_30')
            : t('BOOKING.RESULTS.REFRESH')
        }}
      </button>
    </div>

    <template v-else>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="row in rows"
          :key="row.id"
          :data-row="row.id"
          class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex flex-col min-w-0 gap-0.5">
            <span class="text-sm font-semibold truncate text-n-slate-12">
              {{ row.contact.name }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ openedText(row) }}{{ SEPARATOR }}{{ viaText(row) }}
            </span>
            <span
              v-if="notices[row.id]"
              role="alert"
              class="text-sm text-n-ruby-11"
              data-row-error
            >
              {{ notices[row.id] }}
            </span>
          </div>
          <span
            v-if="row.resent_at"
            role="status"
            data-resent
            tabindex="-1"
            class="self-start px-3 py-1 text-sm font-medium rounded-full sm:self-center bg-n-teal-3 text-n-teal-11"
          >
            {{ t('BOOKING.RESULTS.LIST.RESENT') }}
          </span>
          <button
            v-else-if="row.can_resend"
            type="button"
            data-resend
            :disabled="sendingId === row.id"
            :aria-label="
              t('BOOKING.RESULTS.LIST.RESEND_LABEL', { name: row.contact.name })
            "
            class="inline-flex items-center justify-center gap-2 min-h-11 px-4 rounded-xl text-sm font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="resend(row)"
          >
            <span class="i-lucide-send size-4" aria-hidden="true" />
            {{ t('BOOKING.RESULTS.LIST.RESEND') }}
          </button>
          <span
            v-else-if="canSend"
            class="text-sm text-n-slate-11"
            data-no-conversation
          >
            {{ t('BOOKING.RESULTS.LIST.NO_CONVERSATION') }}
          </span>
        </li>
      </ul>
      <button
        v-if="hasMore"
        type="button"
        data-list-more
        :disabled="loadingMore"
        class="self-center min-h-11 px-4 rounded-xl text-sm font-semibold text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-2 disabled:opacity-60 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="loadMore"
      >
        {{ t('BOOKING.RESULTS.LIST.MORE') }}
      </button>
    </template>
  </section>
</template>
