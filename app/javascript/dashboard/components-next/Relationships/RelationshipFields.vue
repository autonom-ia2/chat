<script setup>
import { computed } from 'vue';
import { useRelationships } from 'dashboard/composables/useRelationships';
import FieldConfigurator from './FieldConfigurator.vue';
import FieldEditor from './FieldEditor.vue';
import { selectDefinitions } from './presentation';
const props = defineProps({
  record: { type: Object, required: true },
  entity: { type: String, required: true },
  surface: { type: String, required: true },
});
const { attributesEnabled, companiesEnabled, state, accountId } =
  useRelationships();
const fields = computed(() =>
  selectDefinitions(
    state.value.definitions.filter(
      item => item.attribute_model === `${props.entity}_attribute`
    ),
    state.value.configuration,
    props.surface
  )
);
</script>

<template>
  <section
    v-if="attributesEnabled && (entity !== 'company' || companiesEnabled)"
    class="w-full flex flex-col gap-2"
  >
    <h3 class="text-base font-medium">{{ $t('RELATIONSHIPS.FIELDS') }}</h3>
    <FieldConfigurator :entity="entity" :surface="surface" />
    <FieldEditor
      v-for="definition in fields"
      :key="`${accountId}-${record.id}-${definition.id}`"
      :definition="definition"
      :record="record"
      :entity="entity"
    />
  </section>
</template>
