<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useRelationships } from 'dashboard/composables/useRelationships';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import RelationshipBreadcrumb from './RelationshipBreadcrumb.vue';
const { navigationEnabled, accountId } = useRelationships();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const segments = useMapGetter('customViews/getContactCustomViews');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const views = computed(() => [
  {
    value: 'all',
    label: t('SIDEBAR.ALL_CONTACTS'),
    name: 'contacts_dashboard_index',
  },
  {
    value: 'active',
    label: t('SIDEBAR.ACTIVE'),
    name: 'contacts_dashboard_active',
  },
  ...segments.value.map(segment => ({
    value: `segment-${segment.id}`,
    label: `${t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS')}: ${segment.name}`,
    name: 'contacts_dashboard_segments_index',
    params: { segmentId: segment.id },
  })),
  ...labels.value.map(label => ({
    value: `label-${label.title}`,
    label: `${t('SIDEBAR.TAGGED_WITH')}: ${label.title}`,
    name: 'contacts_dashboard_labels_index',
    params: { label: label.title },
  })),
]);
const selected = computed(() => {
  if (route.params.segmentId) return `segment-${route.params.segmentId}`;
  if (route.params.label) return `label-${route.params.label}`;
  return route.name === 'contacts_dashboard_active' ? 'active' : 'all';
});
const change = value => {
  const view = views.value.find(item => item.value === value);
  router.push({
    name: view.name,
    params: { accountId: accountId.value, ...view.params },
    query: { page: 1 },
  });
};
</script>

<template>
  <div v-if="navigationEnabled" class="flex items-center gap-3 px-4 py-2">
    <RelationshipBreadcrumb />
    <ChoiceSelect
      :model-value="selected"
      :options="views.map(({ value, label }) => ({ value, label }))"
      :aria-label="t('RELATIONSHIPS.VIEW')"
      compact
      @update:model-value="change"
    />
  </div>
</template>
