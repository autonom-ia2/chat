<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Icon from 'dashboard/components-next/icon/Icon.vue';
const props = defineProps({ items: { type: Array, default: null } });
const { navigationEnabled, accountId } = useRelationships();
const route = useRoute();
const trail = computed(() => {
  if (props.items) return props.items;
  const name = String(route.name || '');
  if (name.startsWith('contacts_')) return [{ key: 'CONTACTS' }];
  if (name.startsWith('companies_') || name === 'relationships_company_media')
    return [{ key: 'COMPANIES' }];
  if (name === 'attributes_list') return [{ key: 'ATTRIBUTES' }];
  return [];
});
</script>

<template>
  <nav
    v-if="navigationEnabled"
    :aria-label="$t('RELATIONSHIPS.BREADCRUMB_LABEL')"
    class="min-w-0 text-sm"
  >
    <ol
      class="m-0 flex min-w-0 list-none flex-wrap items-center gap-x-2 gap-y-1 p-0"
    >
      <li class="flex list-none">
        <RouterLink
          :to="{ name: 'relationships_home', params: { accountId } }"
          class="rounded text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        >
          {{ $t('RELATIONSHIPS.TITLE') }}
        </RouterLink>
      </li>
      <li
        v-for="(item, index) in trail"
        :key="index"
        class="flex min-w-0 items-center gap-2"
      >
        <Icon
          icon="i-lucide-chevron-right"
          class="size-3.5 shrink-0 text-n-slate-9 rtl:rotate-180"
        />
        <RouterLink
          v-if="item.to"
          :to="item.to"
          class="truncate rounded text-n-slate-11 hover:text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        >
          {{ item.label || $t(`RELATIONSHIPS.${item.key}`) }}
        </RouterLink>
        <span
          v-else
          :aria-current="index === trail.length - 1 ? 'page' : undefined"
          class="max-w-64 truncate font-medium text-n-slate-12"
          >{{ item.label || $t(`RELATIONSHIPS.${item.key}`) }}</span
        >
      </li>
    </ol>
  </nav>
  <template v-else />
</template>
