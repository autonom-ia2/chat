<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="rounded-md border border-emerald-100 bg-emerald-50/70 p-4 text-sm text-emerald-950"
  >
    <div class="mb-3 flex flex-wrap items-center gap-2">
      <span
        class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800 ring-1 ring-emerald-200"
      >
        <span class="i-lucide-sparkles size-3.5" />
        {{ t('PROSPECTING.SEARCH.ENRICHMENT_TITLE') }}
      </span>
      <span class="text-xs font-medium text-emerald-700">
        {{ t('PROSPECTING.SEARCH.ENRICHMENT_COMPLETED') }}
      </span>
    </div>

    <div class="grid gap-3">
      <div v-if="lead.enrichment_summary">
        <div class="text-xs font-semibold text-emerald-800">
          {{ t('PROSPECTING.SEARCH.ENRICHMENT_SUMMARY') }}
        </div>
        <div class="mt-1 whitespace-pre-line break-words leading-relaxed">
          {{ lead.enrichment_summary }}
        </div>
      </div>

      <div v-if="lead.decision_name">
        <div class="text-xs font-semibold text-emerald-800">
          {{ t('PROSPECTING.SEARCH.DECISION_MAKER') }}
        </div>
        <div class="mt-1 break-words leading-relaxed">
          {{ lead.decision_name }}
          <span v-if="lead.decision_role">
            {{ `· ${lead.decision_role}` }}
          </span>
        </div>
      </div>

      <div
        v-if="
          lead.enriched_email ||
          lead.enriched_whatsapp ||
          lead.enriched_instagram ||
          lead.enriched_facebook ||
          lead.enriched_linkedin ||
          lead.enriched_cnpj
        "
        class="grid gap-2 sm:grid-cols-2"
      >
        <div v-if="lead.enriched_email" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_EMAIL')}:` }}
          </span>
          {{ lead.enriched_email }}
        </div>
        <div v-if="lead.enriched_whatsapp" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_WHATSAPP')}:` }}
          </span>
          {{ lead.enriched_whatsapp }}
        </div>
        <div v-if="lead.enriched_instagram" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_INSTAGRAM')}:` }}
          </span>
          {{ lead.enriched_instagram }}
        </div>
        <div v-if="lead.enriched_facebook" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_FACEBOOK')}:` }}
          </span>
          {{ lead.enriched_facebook }}
        </div>
        <div v-if="lead.enriched_linkedin" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_LINKEDIN')}:` }}
          </span>
          {{ lead.enriched_linkedin }}
        </div>
        <div v-if="lead.enriched_cnpj" class="break-words">
          <span class="font-semibold">
            {{ `${t('PROSPECTING.SEARCH.ENRICHED_CNPJ')}:` }}
          </span>
          {{ lead.enriched_cnpj }}
        </div>
      </div>
    </div>
  </div>
</template>
