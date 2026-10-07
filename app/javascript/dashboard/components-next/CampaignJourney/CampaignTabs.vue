<script setup>
// Tabs at the top of Campanhas › Campanha (#1076): "Campanhas" and, when the account sends
// e-mail and the identity flag is on, "Identidade visual". Both stay under the "Campanha" entry
// of the menu.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBrandKits } from 'dashboard/components-next/BrandKits/useBrandKits';

defineProps({
  active: { type: String, required: true },
});

const { t } = useI18n();
const { isAvailable } = useBrandKits();

const tabs = computed(() => [
  {
    key: 'campaigns',
    label: t('BRAND_KITS.TABS.CAMPAIGNS'),
    to: { name: 'campaigns_journey_index' },
  },
  ...(isAvailable.value
    ? [
        {
          key: 'identity',
          label: t('BRAND_KITS.TABS.IDENTITY'),
          to: { name: 'campaigns_journey_brand_kits' },
        },
      ]
    : []),
]);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <nav
    v-if="tabs.length > 1"
    class="mb-6 flex gap-1 border-b border-n-weak"
    :aria-label="t('BRAND_KITS.TABS.LABEL')"
  >
    <router-link
      v-for="tab in tabs"
      :key="tab.key"
      :to="tab.to"
      class="-mb-px flex min-h-11 items-center border-b-2 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        active === tab.key
          ? 'border-n-blue-9 text-n-blue-11'
          : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
      "
      :aria-current="active === tab.key ? 'page' : undefined"
      :data-tab="tab.key"
    >
      {{ tab.label }}
    </router-link>
  </nav>
</template>
