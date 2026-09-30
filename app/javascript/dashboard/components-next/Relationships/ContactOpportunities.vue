<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

defineProps({ list: { type: Object, required: true } });
const { t, locale } = useI18n();
const { accountId } = useAccount();
// Account catalogs use pt_BR; browser Intl requires the BCP 47 spelling pt-BR.
const intlLocale = computed(() => locale.value.replace('_', '-'));
const label = key => t(`CRM_KANBAN.CONTACT_OPPORTUNITIES.${key}`);
const results = computed(() => [
  { value: 'active', label: label('ACTIVE') },
  { value: 'all', label: label('ALL') },
  ...['open', 'won', 'lost', 'archived'].map(value => ({
    value,
    label: t(`CRM_KANBAN.DRAWER.STATUS_${value.toUpperCase()}`),
  })),
]);
const tones = {
  open: 'bg-n-blue-3 text-n-blue-11',
  won: 'bg-n-teal-3 text-n-teal-11',
  lost: 'bg-n-ruby-3 text-n-ruby-11',
  archived: 'bg-n-slate-4 text-n-slate-11',
};
const amount = card => {
  try {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: card.currency,
    }).format(card.value_cents / 100);
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
    // The native API permits arbitrary currency strings; never invent a BRL conversion.
    return `${card.currency} ${new Intl.NumberFormat(intlLocale.value, { minimumFractionDigits: 2 }).format(card.value_cents / 100)}`;
  }
};
// Match the CRM date input (expected_close_at.slice(0, 10)), not the prior
// calendar day when a date-only forecast is persisted at midnight UTC.
const forecast = value =>
  new Intl.DateTimeFormat(intlLocale.value, { timeZone: 'UTC' }).format(
    new Date(value)
  );
const destination = card => ({
  name: 'crm_kanban_index',
  params: { accountId: accountId.value },
  query: { card_id: String(card.id) },
});
</script>

<template>
  <section
    class="grid min-w-0 gap-4 px-4 py-3 sm:px-6"
    data-contact-opportunities
    :aria-busy="list.loading"
  >
    <header class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h3
          class="m-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-panels-top-left size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ label('TITLE') }}
        </h3>
        <p class="mb-0 mt-2 text-xs leading-5 text-n-slate-11">
          {{ label('HELP') }}
        </p>
      </div>
      <Button
        type="button"
        sm
        ghost
        slate
        icon="i-lucide-refresh-cw"
        :aria-label="label('REFRESH')"
        :title="label('REFRESH')"
        :disabled="list.loading"
        @click="list.load()"
      />
    </header>
    <form class="flex min-w-0 items-end gap-2" @submit.prevent="list.apply()">
      <Input
        :model-value="list.state.query"
        class="min-w-0 flex-1"
        :label="label('SEARCH')"
        :placeholder="label('SEARCH_HINT')"
        :maxlength="200"
        :disabled="list.loading"
        @update:model-value="list.setQuery($event)"
      />
      <Button
        type="submit"
        faded
        slate
        icon="i-lucide-search"
        :aria-label="label('APPLY_SEARCH')"
        :title="label('APPLY_SEARCH')"
        :disabled="list.loading"
      />
    </form>
    <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
      <span>{{ label('RESULT') }}</span>
      <ChoiceSelect
        :model-value="list.state.result"
        :options="results"
        :aria-label="label('RESULT')"
        :disabled="list.loading"
        @update:model-value="list.setResult($event)"
      />
    </label>
    <div
      v-if="list.loading"
      role="status"
      class="flex items-center gap-2 rounded-xl border border-n-weak p-5 text-sm text-n-slate-11"
    >
      <span
        class="i-lucide-loader-circle size-4 animate-spin"
        aria-hidden="true"
      />{{ label('LOADING') }}
    </div>
    <div
      v-else-if="list.state.failed"
      role="alert"
      class="grid gap-3 rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
    >
      <p class="m-0">{{ label('ERROR') }}</p>
      <Button
        type="button"
        sm
        ghost
        :label="label('RETRY')"
        class="justify-self-start"
        @click="list.load()"
      />
    </div>
    <template v-else-if="list.state.loaded">
      <p class="m-0 text-xs text-n-slate-11" role="status">
        {{
          t('CRM_KANBAN.CONTACT_OPPORTUNITIES.COUNT', {
            count: list.state.total,
          })
        }}
      </p>
      <div v-if="list.state.items.length" class="grid min-w-0 gap-3">
        <RouterLink
          v-for="card in list.state.items"
          :key="card.id"
          :to="destination(card)"
          target="_blank"
          rel="noopener noreferrer"
          :aria-label="
            t('CRM_KANBAN.CONTACT_OPPORTUNITIES.OPEN', { title: card.title })
          "
          class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-n-slate-12 hover:border-n-brand/40 hover:bg-n-brand/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-contact-opportunity
        >
          <div class="flex min-w-0 items-start justify-between gap-3">
            <h4 class="m-0 min-w-0 break-words text-sm font-semibold">
              {{ card.title }}
            </h4>
            <span
              class="i-lucide-external-link mt-0.5 size-4 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
          </div>
          <p class="m-0 break-words text-xs leading-5 text-n-slate-11">
            {{ [card.pipeline.name, card.stage.name].join(' · ') }}
          </p>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div
              class="rounded-md px-2 py-1 text-xs font-medium"
              :class="tones[card.status]"
            >
              {{ t(`CRM_KANBAN.DRAWER.STATUS_${card.status.toUpperCase()}`) }}
            </div>
            <span class="text-sm font-semibold">{{ amount(card) }}</span>
          </div>
          <div
            class="flex flex-wrap items-center justify-between gap-2 border-t border-n-weak pt-3 text-xs text-n-slate-11"
          >
            <div class="flex min-w-0 items-center gap-1.5">
              <span
                class="i-lucide-user-round size-3.5 shrink-0"
                aria-hidden="true"
              />
              {{ card.owner?.name || label('NO_OWNER') }}
            </div>
            <p v-if="card.expected_close_at" class="m-0">
              {{ label('FORECAST') }} {{ forecast(card.expected_close_at) }}
            </p>
          </div>
        </RouterLink>
      </div>
      <div
        v-else
        class="grid justify-items-center gap-2 rounded-xl border border-dashed border-n-strong px-4 py-8 text-center"
        data-opportunities-empty
      >
        <span
          class="i-lucide-folder-search size-7 text-n-slate-10"
          aria-hidden="true"
        />
        <h4 class="m-0 text-sm font-medium text-n-slate-12">
          {{ label('EMPTY') }}
        </h4>
        <p class="m-0 text-xs leading-5 text-n-slate-11">
          {{ label('EMPTY_HELP') }}
        </p>
      </div>
      <nav
        v-if="list.state.page > 1 || list.state.hasMore"
        class="flex items-center justify-between gap-2"
        :aria-label="label('PAGINATION')"
      >
        <Button
          type="button"
          sm
          ghost
          slate
          :label="label('PREVIOUS')"
          :disabled="list.state.page <= 1"
          @click="list.load(list.state.page - 1)"
        />
        <span class="text-xs text-n-slate-11">{{
          t('CRM_KANBAN.CONTACT_OPPORTUNITIES.PAGE', { page: list.state.page })
        }}</span>
        <Button
          type="button"
          sm
          ghost
          slate
          :label="label('NEXT')"
          :disabled="!list.state.hasMore"
          @click="list.load(list.state.page + 1)"
        />
      </nav>
    </template>
  </section>
</template>
