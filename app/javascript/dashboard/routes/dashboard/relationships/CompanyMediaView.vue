<script setup>
import { useRoute } from 'vue-router';
import { useRelationships } from 'dashboard/composables/useRelationships';
import CompanyMedia from 'dashboard/components-next/Relationships/CompanyMedia.vue';
const route = useRoute();
const { mediaEnabled, accountId } = useRelationships();
</script>

<template>
  <main
    v-if="mediaEnabled"
    class="flex-1 min-w-0 overflow-auto bg-n-surface-1 p-6"
  >
    <RouterLink
      :to="{
        name: 'companies_dashboard_show',
        params: { accountId, companyId: route.params.companyId },
        query: route.query,
      }"
      class="text-n-blue-11"
    >
      {{ $t('RELATIONSHIPS.BACK') }}
    </RouterLink>
    <h1 class="text-xl font-semibold mt-4">
      {{ $t('RELATIONSHIPS.MEDIA.TITLE') }}
    </h1>
    <CompanyMedia :company-id="Number(route.params.companyId)" expanded />
  </main>
  <template v-else />
</template>
