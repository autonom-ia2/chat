<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Policy from 'dashboard/components/policy.vue';
const { navigationEnabled, accountId } = useRelationships();
const { isCloudFeatureEnabled } = useAccount();
const cards = computed(() =>
  [
    {
      title: 'CONTACTS',
      route: 'contacts_dashboard_index',
      flag: 'crm',
      permissions: ['administrator', 'agent', 'contact_view', 'contact_manage'],
      icon: 'i-lucide-contact',
    },
    {
      title: 'COMPANIES',
      route: 'companies_dashboard_index',
      flag: 'companies',
      permissions: ['administrator', 'agent'],
      icon: 'i-lucide-building-2',
      installationTypes: ['cloud', 'enterprise'],
    },
    {
      title: 'ATTRIBUTES',
      route: 'attributes_list',
      flag: 'custom_attributes',
      permissions: ['administrator', 'attribute_manage'],
      icon: 'i-lucide-list-filter',
    },
  ].filter(card => isCloudFeatureEnabled(card.flag))
);
</script>

<template>
  <main
    v-if="navigationEnabled"
    class="flex-1 bg-n-surface-1 p-6 md:p-10 overflow-auto"
  >
    <h1 class="text-2xl font-semibold text-n-slate-12">
      {{ $t('RELATIONSHIPS.TITLE') }}
    </h1>
    <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
      <Policy
        v-for="card in cards"
        :key="card.route"
        :feature-flag="card.flag"
        :permissions="card.permissions"
        :installation-types="card.installationTypes"
      >
        <RouterLink
          :to="{ name: card.route, params: { accountId } }"
          class="flex flex-col gap-3 border border-n-weak rounded-xl p-6 h-full hover:border-n-blue-9 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        >
          <span :class="card.icon" class="size-6 text-n-blue-11" />
          <h2 class="text-lg font-medium">
            {{ $t(`RELATIONSHIPS.${card.title}`) }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ $t(`RELATIONSHIPS.CARDS.${card.title}`) }}
          </p>
        </RouterLink>
      </Policy>
    </div>
  </main>
  <template v-else />
</template>
