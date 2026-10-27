<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { relativeTime } from '../metaAdsHelpers';
import { phoneLabel } from '../semLogin/anunciosSemLogin';

// Quem chegou pelos formulários (#2195): cada pessoa já virou card no funil escolhido, com o anúncio de origem.
defineProps({
  leads: { type: Array, required: true },
});

const KEY = 'CRM_KANBAN.META_ADS_HUB.LEAD_FORMS.RECENT';
const { locale } = useI18n();
const route = useRoute();

const cardLink = lead => ({
  name: 'crm_kanban_index',
  params: { accountId: route.params.accountId },
  query: {
    pipeline_id: String(lead.pipeline_id),
    ...(lead.card_id ? { card_id: String(lead.card_id) } : {}),
  },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
    data-lead-recent
  >
    <h4 class="m-0 text-base font-semibold text-n-slate-12">
      {{ $t(`${KEY}.TITLE`) }}
    </h4>
    <p v-if="!leads.length" class="m-0 text-sm text-n-slate-11">
      {{ $t(`${KEY}.EMPTY`) }}
    </p>
    <ul v-else class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
      <li
        v-for="lead in leads"
        :key="lead.id"
        :data-lead="lead.id"
        class="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex flex-col min-w-0 gap-0.5">
          <span class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ lead.name }}
            </span>
            <span
              class="px-2 py-0.5 text-xs rounded-full"
              :class="
                lead.new_contact
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ lead.new_contact ? $t(`${KEY}.NEW`) : $t(`${KEY}.KNOWN`) }}
            </span>
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              [phoneLabel(lead.phone), lead.email].filter(Boolean).join(' · ')
            }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              $t(`${KEY}.ORIGIN`, {
                form: lead.form_name,
                ad: lead.ad_name,
                when: relativeTime(lead.received_at, locale),
              })
            }}
          </span>
        </div>
        <router-link
          :to="cardLink(lead)"
          class="inline-flex items-center self-start gap-1 px-3 text-sm font-semibold rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-1 sm:self-auto focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        >
          {{
            $t(`${KEY}.OPEN`, {
              pipeline: lead.pipeline_name,
              stage: lead.stage_name,
            })
          }}
          <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
        </router-link>
      </li>
    </ul>
  </section>
</template>
