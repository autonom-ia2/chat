<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import ListAttribute from 'dashboard/components-next/CustomAttributes/ListAttribute.vue';
import CheckboxAttribute from 'dashboard/components-next/CustomAttributes/CheckboxAttribute.vue';
import DateAttribute from 'dashboard/components-next/CustomAttributes/DateAttribute.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';

const props = defineProps({
  card: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const NUMERIC_TYPES = ['number', 'currency', 'percent'];
const componentMap = {
  list: ListAttribute,
  checkbox: CheckboxAttribute,
  date: DateAttribute,
};

const values = ref({ ...(props.card.custom_attributes || {}) });
watch(
  () => props.card.custom_attributes,
  next => {
    values.value = { ...(next || {}) };
  }
);

// Same gate as the Settings → Custom attributes route: administrators or `attribute_manage` seats.
const canCreateFields = computed(() => {
  if (store.getters.getCurrentRole === 'administrator') return true;
  const user = store.getters.getCurrentUser;
  if (!user?.accounts) return false;
  return getUserPermissions(user, store.getters.getCurrentAccountId).includes(
    'attribute_manage'
  );
});
const definitions = computed(
  () => store.getters['attributes/getCardAttributes'] || []
);
const fields = computed(() =>
  definitions.value.map(definition => ({
    ...definition,
    // The shared inputs only know text/number/link; currency and percent are typed as numbers.
    attributeDisplayType: NUMERIC_TYPES.includes(
      definition.attributeDisplayType
    )
      ? 'number'
      : definition.attributeDisplayType,
    value: values.value[definition.attributeKey] ?? '',
  }))
);
const isVisible = computed(
  () => definitions.value.length > 0 || canCreateFields.value
);
const settingsRoute = computed(() => ({
  name: 'attributes_list',
  params: { accountId: route.params.accountId },
}));

const readOnlyValue = field => {
  if (typeof field.value === 'boolean')
    return field.value
      ? t('CRM_KANBAN.RELATIONSHIP.VALUE_YES')
      : t('CRM_KANBAN.RELATIONSHIP.VALUE_NO');
  return field.value === '' || field.value == null
    ? t('CRM_KANBAN.RELATIONSHIP.NOT_INFORMED')
    : field.value;
};

const normalize = (field, value) => {
  if (value === null || !NUMERIC_TYPES.includes(field.attributeDisplayType))
    return value;
  return Number(value);
};

const persist = async (field, value, messages) => {
  if (!props.canManage) return;
  try {
    const updated = await store.dispatch('crmKanban/updateCard', {
      id: props.card.id,
      custom_attributes: { [field.attributeKey]: normalize(field, value) },
    });
    values.value = { ...(updated?.custom_attributes || {}) };
    useAlert(messages.success);
  } catch {
    useAlert(messages.error);
  }
};

const updateField = (field, value) =>
  persist(field, value, {
    success: t('CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_SUCCESS'),
    error: t('CRM_KANBAN.DRAWER.CARD_FIELDS.UPDATE_ERROR'),
  });

const clearField = field =>
  persist(field, null, {
    success: t('CRM_KANBAN.DRAWER.CARD_FIELDS.DELETE_SUCCESS'),
    error: t('CRM_KANBAN.DRAWER.CARD_FIELDS.DELETE_ERROR'),
  });

onMounted(() => {
  store.dispatch('attributes/get');
});
</script>

<template>
  <section
    v-show="isVisible"
    class="grid gap-3 rounded-xl border border-n-weak bg-n-surface-1 p-4"
    data-testid="crm-card-custom-fields"
  >
    <div class="min-w-0">
      <p class="mb-1 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.DRAWER.CARD_FIELDS.TITLE') }}
      </p>
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('CRM_KANBAN.DRAWER.CARD_FIELDS.HELP') }}
      </p>
    </div>

    <div
      v-if="fields.length"
      class="grid divide-y divide-n-weak"
      data-testid="crm-card-custom-fields-list"
    >
      <div
        v-for="field in fields"
        :key="`${card.id}-${field.id}`"
        class="group/attribute grid min-h-10 w-full grid-cols-[140px,1fr] items-center gap-2 py-1"
        :data-field="field.attributeKey"
      >
        <span class="truncate text-sm font-medium text-n-slate-12">
          {{ field.attributeDisplayName }}
        </span>
        <component
          :is="componentMap[field.attributeDisplayType] || OtherAttribute"
          v-if="canManage"
          :attribute="field"
          is-editing-view
          @update="value => updateField(field, value)"
          @delete="clearField(field)"
        />
        <span v-else class="break-words text-sm text-n-slate-12">
          {{ readOnlyValue(field) }}
        </span>
      </div>
    </div>

    <div
      v-else
      class="grid justify-items-start gap-2"
      data-testid="crm-card-custom-fields-empty"
    >
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('CRM_KANBAN.DRAWER.CARD_FIELDS.EMPTY_ADMIN') }}
      </p>
      <router-link
        :to="settingsRoute"
        class="inline-flex min-h-11 items-center text-sm font-medium text-n-blue-11 hover:underline"
      >
        {{ t('CRM_KANBAN.DRAWER.CARD_FIELDS.OPEN_SETTINGS') }}
      </router-link>
    </div>
  </section>
</template>
