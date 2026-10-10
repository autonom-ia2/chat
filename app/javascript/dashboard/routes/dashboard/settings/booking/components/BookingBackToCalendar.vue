<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// O Agendamento mora no CRM (#1212): quem chegou pelo botão do Calendário
// volta para ele por aqui. Função só com Agendamento não abre o Calendário,
// então o link não aparece para ela.
const { t } = useI18n();
const route = useRoute();
const { canViewCrm } = useCrmPermissions();
</script>

<template>
  <div class="contents">
    <router-link
      v-if="canViewCrm"
      :to="{ name: 'crm_calendar_index', params: route.params }"
      data-back-to-calendar
      class="inline-flex items-center gap-1 -mb-4 min-h-11 w-fit text-sm font-medium text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    >
      <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
      {{ t('BOOKING.PAGE.BACK_TO_CALENDAR') }}
    </router-link>
  </div>
</template>
