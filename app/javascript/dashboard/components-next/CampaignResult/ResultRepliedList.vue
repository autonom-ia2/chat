<script setup>
// "Quem respondeu" of an e-mail campaign (#1007, E3): the contacts whose conversation got the
// campaign mark, each with "Abrir conversa". The full per-person table of the e-mail stays the
// e-mail reports one (EmailRecipients), with every filter and export it already had.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  channel: { type: String, required: true },
  campaignId: { type: [String, Number], required: true },
  refreshKey: { type: Number, default: 0 },
});

const NS = 'RESULT_JOURNEY.REPLIED';
const { t } = useI18n();
const rows = ref([]);
const meta = ref({});
const page = ref(1);
const hasError = ref(false);
const isLoading = ref(false);

const fetchRows = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await CampaignResultsAPI.getRecipients(
      props.channel,
      props.campaignId,
      { status: 'replied', page: page.value }
    );
    rows.value = data.payload.rows || [];
    meta.value = data.payload.meta || {};
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const goTo = value => {
  page.value = value;
  fetchRows();
};

watch(
  () => [props.campaignId, props.refreshKey],
  () => fetchRows(),
  { immediate: true }
);
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    data-replied-list
  >
    <h2 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t(`${NS}.TITLE`) }}
    </h2>
    <p v-if="hasError" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ t('RESULT_JOURNEY.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="!rows.length && !isLoading"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t(`${NS}.EMPTY`) }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col p-0">
      <li
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center justify-between gap-2 border-b border-n-weak py-2 last:border-0"
      >
        <div class="min-w-0">
          <p class="mb-0 break-words text-sm font-medium text-n-slate-12">
            {{ row.contact.name || '—' }}
          </p>
          <bdi dir="ltr" class="block text-xs text-n-slate-11">
            {{ row.contact.email || '' }}
          </bdi>
        </div>
        <router-link
          v-if="row.conversation_display_id"
          :to="{
            name: 'inbox_conversation',
            params: { conversation_id: row.conversation_display_id },
          }"
          class="flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          data-open-conversation
        >
          {{ t('RESULT_JOURNEY.PEOPLE.OPEN_CONVERSATION') }}
          <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
        </router-link>
      </li>
    </ul>
    <div
      v-if="(meta.total_pages || 1) > 1"
      class="flex flex-wrap items-center justify-end gap-2 text-sm text-n-slate-11"
    >
      <Button
        :label="t('RESULT_JOURNEY.PEOPLE.PREV')"
        slate
        outline
        class="!min-h-11"
        :disabled="isLoading || page <= 1"
        @click="goTo(page - 1)"
      />
      <Button
        :label="t('RESULT_JOURNEY.PEOPLE.NEXT')"
        slate
        outline
        class="!min-h-11"
        :disabled="isLoading || page >= meta.total_pages"
        @click="goTo(page + 1)"
      />
    </div>
  </section>
</template>
