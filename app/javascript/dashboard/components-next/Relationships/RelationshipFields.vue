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
    class="w-full min-w-0 flex flex-col gap-5 border-t border-n-weak pt-6"
  >
    <div class="flex flex-col gap-4">
      <div>
        <h3 class="text-lg font-semibold text-n-slate-12">
          {{ $t('RELATIONSHIPS.FIELDS') }}
        </h3>
        <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
          {{ $t('RELATIONSHIPS.FIELDS_DESCRIPTION') }}
        </p>
      </div>
      <FieldConfigurator :entity="entity" :surface="surface" />
    </div>
    <div
      v-if="fields.length"
      class="grid min-w-0 grid-cols-1 gap-3 2xl:grid-cols-2"
    >
      <FieldEditor
        v-for="definition in fields"
        :key="`${accountId}-${record.id}-${definition.id}`"
        :definition="definition"
        :record="record"
        :entity="entity"
      />
    </div>
    <div
      v-else-if="!state.error && !state.loading"
      class="rounded-xl border border-dashed border-n-strong bg-n-background px-5 py-6"
    >
      <p class="text-sm font-medium text-n-slate-12">
        {{ $t('RELATIONSHIPS.FIELDS_EMPTY') }}
      </p>
      <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
        {{ $t('RELATIONSHIPS.FIELDS_EMPTY_DESCRIPTION') }}
      </p>
    </div>
  </section>
  <template v-else />
</template>
