<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import AutonomiaFinancialAPI from 'dashboard/api/autonomia/financial';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  extractErrorMessage,
  formatDate,
  formatMoney,
  invoiceStatusLabel,
  paymentStatusLabel,
  statusToneClass,
  unwrapCollection,
} from '../helpers';

const { t } = useI18n();
const { resolvedLocale } = useLocale();

const isLoading = ref(true);
const errorMessage = ref('');
const invoices = ref([]);
const payments = ref([]);

const openInvoices = computed(() =>
  invoices.value.filter(invoice =>
    ['pending', 'overdue'].includes(invoice.status)
  )
);
const paidInvoices = computed(() =>
  invoices.value.filter(invoice => invoice.status === 'paid')
);
const openAmount = computed(() =>
  openInvoices.value.reduce(
    (sum, invoice) => sum + Number(invoice.amount || 0),
    0
  )
);
const currency = computed(
  () => invoices.value[0]?.currency || payments.value[0]?.currency || 'BRL'
);

const load = async () => {
  isLoading.value = true;
  errorMessage.value = '';

  try {
    const [invoicesResponse, paymentsResponse] = await Promise.all([
      AutonomiaFinancialAPI.invoices(),
      AutonomiaFinancialAPI.payments(),
    ]);
    invoices.value = unwrapCollection(invoicesResponse.data);
    payments.value = unwrapCollection(paymentsResponse.data);
  } catch (error) {
    errorMessage.value =
      extractErrorMessage(error) || t('FINANCIAL.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <main class="h-full overflow-auto bg-n-surface-1">
    <section class="max-w-6xl px-6 py-8 mx-auto space-y-6">
      <header class="flex flex-col gap-1">
        <span
          class="text-xs font-medium tracking-wide uppercase text-n-slate-11"
        >
          {{ t('FINANCIAL.INVOICES.EYEBROW') }}
        </span>
        <div class="flex items-center justify-between gap-3">
          <div>
            <h1 class="text-2xl font-semibold text-n-slate-12">
              {{ t('FINANCIAL.INVOICES.TITLE') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ t('FINANCIAL.INVOICES.DESCRIPTION') }}
            </p>
          </div>
          <Button
            icon="i-lucide-refresh-cw"
            :label="t('FINANCIAL.REFRESH')"
            color="slate"
            variant="faded"
            size="sm"
            @click="load"
          />
        </div>
      </header>

      <div v-if="isLoading" class="flex items-center justify-center py-24">
        <Spinner />
      </div>

      <div
        v-else-if="errorMessage"
        class="p-4 border rounded-lg border-red-200 bg-red-50 text-red-900 dark:bg-red-950/30 dark:text-red-100 dark:border-red-900"
      >
        {{ errorMessage }}
      </div>

      <template v-else>
        <section class="grid gap-3 md:grid-cols-3">
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">
              {{ t('FINANCIAL.INVOICES.OPEN') }}
            </p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ formatMoney(openAmount, currency, resolvedLocale) }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{
                t('FINANCIAL.INVOICES.OPEN_HINT', { n: openInvoices.length })
              }}
            </p>
          </article>
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">
              {{ t('FINANCIAL.INVOICES.PAID') }}
            </p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ paidInvoices.length }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ t('FINANCIAL.INVOICES.PAID_HINT') }}
            </p>
          </article>
          <article class="p-4 border rounded-lg bg-n-solid-1 border-n-weak">
            <p class="text-sm text-n-slate-11">
              {{ t('FINANCIAL.INVOICES.PAYMENTS') }}
            </p>
            <strong class="block mt-2 text-xl font-semibold text-n-slate-12">
              {{ payments.length }}
            </strong>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ t('FINANCIAL.INVOICES.PAYMENTS_HINT') }}
            </p>
          </article>
        </section>

        <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('FINANCIAL.INVOICES.TABLE.TITLE') }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('FINANCIAL.INVOICES.TABLE.DESCRIPTION') }}
          </p>
          <div class="mt-4 overflow-hidden border rounded-lg border-n-weak">
            <table class="w-full text-sm">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.AMOUNT') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.STATUS') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.DUE_DATE') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.PAYMENT') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.DOCUMENT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="invoice in invoices"
                  :key="invoice.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-4 py-3 font-medium text-n-slate-12">
                    {{
                      formatMoney(
                        invoice.amount,
                        invoice.currency,
                        resolvedLocale
                      )
                    }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="px-2 py-1 text-xs font-medium rounded-full"
                      :class="statusToneClass(invoice.status)"
                    >
                      {{ invoiceStatusLabel(t, invoice.status) }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(invoice.dueDate, resolvedLocale) }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(invoice.paidAt, resolvedLocale) }}
                  </td>
                  <td class="px-4 py-3">
                    <a
                      v-if="invoice.invoiceUrl"
                      :href="invoice.invoiceUrl"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-n-brand"
                    >
                      {{ t('FINANCIAL.INVOICES.TABLE.OPEN_INVOICE') }}
                    </a>
                    <span v-else class="text-n-slate-10">
                      {{ t('FINANCIAL.UNAVAILABLE') }}
                    </span>
                  </td>
                </tr>
                <tr v-if="!invoices.length">
                  <td colspan="5" class="px-4 py-8 text-center text-n-slate-11">
                    {{ t('FINANCIAL.INVOICES.TABLE.EMPTY') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="p-5 border rounded-lg bg-n-solid-1 border-n-weak">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('FINANCIAL.INVOICES.PAYMENTS_TABLE.TITLE') }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('FINANCIAL.INVOICES.PAYMENTS_TABLE.DESCRIPTION') }}
          </p>
          <div class="mt-4 overflow-hidden border rounded-lg border-n-weak">
            <table class="w-full text-sm">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.AMOUNT') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.TABLE.STATUS') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.PAYMENTS_TABLE.SOURCE') }}
                  </th>
                  <th class="px-4 py-3 text-left">
                    {{ t('FINANCIAL.INVOICES.PAYMENTS_TABLE.PAID_AT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="payment in payments"
                  :key="payment.id"
                  class="border-t border-n-weak"
                >
                  <td class="px-4 py-3 font-medium text-n-slate-12">
                    {{
                      formatMoney(
                        payment.amount,
                        payment.currency,
                        resolvedLocale
                      )
                    }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="px-2 py-1 text-xs font-medium rounded-full"
                      :class="statusToneClass(payment.status)"
                    >
                      {{ paymentStatusLabel(t, payment.status) }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{
                      payment.gateway ||
                      t('FINANCIAL.INVOICES.PAYMENTS_TABLE.MANUAL')
                    }}
                  </td>
                  <td class="px-4 py-3 text-n-slate-11">
                    {{ formatDate(payment.paidAt, resolvedLocale) }}
                  </td>
                </tr>
                <tr v-if="!payments.length">
                  <td colspan="4" class="px-4 py-8 text-center text-n-slate-11">
                    {{ t('FINANCIAL.INVOICES.PAYMENTS_TABLE.EMPTY') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </template>
    </section>
  </main>
</template>
