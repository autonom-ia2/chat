<script setup>
import { useRelationships } from 'dashboard/composables/useRelationships';
const { navigationEnabled, accountId } = useRelationships();
</script>

<template>
  <RouterLink
    v-if="navigationEnabled"
    :to="{ name: 'relationships_home', params: { accountId } }"
    class="text-sm text-n-blue-11 px-2 py-1"
  >
    {{ $t('RELATIONSHIPS.TITLE') }}
  </RouterLink>
  <template v-else />
</template>
