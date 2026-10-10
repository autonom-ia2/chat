<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

// CRM › Agendamento: "Páginas" e "Resultados" (#1194). Links de
// verdade (o endereço muda e dá para favoritar); a aba aberta tem aria-current.
const { t } = useI18n();
const route = useRoute();

const TABS = [
  { name: 'settings_booking', label: 'BOOKING.RESULTS.TAB_PAGES' },
  { name: 'settings_booking_results', label: 'BOOKING.RESULTS.TAB_RESULTS' },
];
</script>

<template>
  <nav :aria-label="t('BOOKING.RESULTS.TABS_LABEL')">
    <ul class="flex gap-1 p-1 m-0 list-none rounded-xl bg-n-alpha-2 w-fit">
      <li v-for="tab in TABS" :key="tab.name">
        <router-link
          :to="{ name: tab.name, params: route.params }"
          :aria-current="route.name === tab.name ? 'page' : undefined"
          :data-tab="tab.name"
          class="inline-flex items-center min-h-11 px-4 rounded-lg text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            route.name === tab.name
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
        >
          {{ t(tab.label) }}
        </router-link>
      </li>
    </ul>
  </nav>
</template>
