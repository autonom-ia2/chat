<script setup>
import { computed, ref, watch, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Button from 'dashboard/components-next/button/Button.vue';
import FieldEditor from 'dashboard/components-next/Relationships/FieldEditor.vue';
import FieldConfigurator from 'dashboard/components-next/Relationships/FieldConfigurator.vue';
import RelationshipMedia from 'dashboard/components-next/Relationships/RelationshipMedia.vue';
import { selectDefinitions } from 'dashboard/components-next/Relationships/presentation';

const props = defineProps({
  contact: { type: Object, required: true },
  company: { type: Object, default: null },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['guard', 'changed']);
const { t } = useI18n();
const {
  accountId,
  attributesEnabled,
  companiesEnabled,
  mediaEnabled,
  state,
  load,
} = useRelationships();
const id = useId();
const fieldsOpen = ref(false);
const mediaOpen = ref(false);
const fieldsEntity = ref('contact');
const mediaEntity = ref('contact');
const expandedMedia = ref(false);
const fieldEditors = ref([]);
const configurator = ref(null);
const hasCompany = computed(
  () => companiesEnabled.value && Boolean(props.company?.id)
);
const record = computed(() =>
  fieldsEntity.value === 'company' ? props.company : props.contact
);
const surface = computed(() =>
  fieldsEntity.value === 'company' ? 'company_details' : 'contact_details'
);
const fields = computed(() =>
  selectDefinitions(
    state.value.definitions.filter(
      item => item.attribute_model === `${fieldsEntity.value}_attribute`
    ),
    state.value.configuration,
    surface.value
  )
);
const dirty = computed(() => fieldEditors.value.some(editor => editor.dirty));
const saving = computed(() => fieldEditors.value.some(editor => editor.busy));
const reset = () => fieldEditors.value.forEach(editor => editor.reset());
const guard = action => emit('guard', action);
const toggleFields = () => {
  if (fieldsOpen.value)
    guard(() => {
      fieldsOpen.value = false;
    });
  else fieldsOpen.value = true;
};
const configure = () => guard(() => configurator.value?.open());
const changeFieldsEntity = entity => {
  if (entity !== fieldsEntity.value)
    guard(() => {
      fieldsEntity.value = entity;
    });
};
const changeMediaEntity = entity => {
  mediaEntity.value = entity;
  expandedMedia.value = false;
};
watch(hasCompany, enabled => {
  if (enabled) return;
  fieldsEntity.value = 'contact';
  mediaEntity.value = 'contact';
  expandedMedia.value = false;
});
defineExpose({ dirty, saving, reset });
</script>

<template>
  <div class="grid min-w-0 gap-4" data-crm-relationship-resources>
    <section
      v-if="attributesEnabled"
      class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1"
      data-crm-fields
    >
      <button
        type="button"
        class="flex min-h-14 w-full items-center gap-3 rounded-xl p-4 text-start text-sm font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-n-brand"
        :aria-expanded="fieldsOpen"
        :aria-controls="`${id}-fields`"
        @click="toggleFields"
      >
        <span
          class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-brand/10 text-n-blue-11"
        >
          <span class="i-lucide-sliders-horizontal size-4" aria-hidden="true" />
        </span>
        <span>{{ t('CRM_KANBAN.RELATIONSHIP.ATTRIBUTES') }}</span>
        <span
          class="i-lucide-chevron-down ms-auto size-4 text-n-slate-11"
          :class="{ 'rotate-180': fieldsOpen }"
          aria-hidden="true"
        />
      </button>
      <div
        v-if="fieldsOpen"
        :id="`${id}-fields`"
        class="grid min-w-0 gap-4 border-t border-n-weak p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div
            class="flex flex-wrap gap-1 rounded-lg bg-n-alpha-black2 p-1"
            :aria-label="t('RELATIONSHIPS.ENTITY')"
            role="group"
          >
            <Button
              sm
              :variant="fieldsEntity === 'contact' ? 'faded' : 'ghost'"
              :aria-pressed="fieldsEntity === 'contact'"
              :label="t('CRM_KANBAN.RELATIONSHIP.FIELDS_CONTACT')"
              @click="changeFieldsEntity('contact')"
            />
            <Button
              v-if="hasCompany"
              sm
              :variant="fieldsEntity === 'company' ? 'faded' : 'ghost'"
              :aria-pressed="fieldsEntity === 'company'"
              :label="t('CRM_KANBAN.RELATIONSHIP.FIELDS_COMPANY')"
              @click="changeFieldsEntity('company')"
            />
          </div>
          <Button
            v-if="state.can_manage && !state.error"
            sm
            ghost
            icon="i-lucide-settings-2"
            :disabled="saving"
            :label="t('RELATIONSHIPS.CONFIGURE')"
            @click="configure"
          />
        </div>
        <p class="m-0 text-xs leading-5 text-n-slate-11">
          {{ t('CRM_KANBAN.RELATIONSHIP.FIELDS_SHARED') }}
        </p>
        <FieldConfigurator
          :key="`${accountId}-${fieldsEntity}`"
          ref="configurator"
          :entity="fieldsEntity"
          :surface="surface"
          :show-actions="false"
        />
        <p
          v-if="state.loading"
          role="status"
          class="m-0 text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIPS.LOADING') }}
        </p>
        <div
          v-if="fields.length && !state.error"
          class="grid min-w-0 grid-cols-1 gap-3 min-[440px]:grid-cols-2"
        >
          <FieldEditor
            v-for="definition in fields"
            :key="`${accountId}-${fieldsEntity}-${record.id}-${definition.id}`"
            ref="fieldEditors"
            :definition="definition"
            :record="record"
            :entity="fieldsEntity"
            :read-only="!canManage"
            @saved="emit('changed')"
          />
        </div>
        <p
          v-else-if="!state.loading && !state.error"
          class="m-0 rounded-lg border border-dashed border-n-strong p-4 text-sm leading-6 text-n-slate-11"
        >
          {{ t('RELATIONSHIPS.FIELDS_EMPTY_DESCRIPTION') }}
        </p>
        <Button
          v-if="state.stale && !state.loading && !state.error"
          sm
          outline
          slate
          :label="t('RELATIONSHIPS.RETRY')"
          @click="load"
        />
      </div>
    </section>
    <section
      v-if="mediaEnabled"
      class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1"
      data-crm-media
    >
      <button
        type="button"
        class="flex min-h-14 w-full items-center gap-3 rounded-xl p-4 text-start text-sm font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-n-brand"
        :aria-expanded="mediaOpen"
        :aria-controls="`${id}-media`"
        @click="mediaOpen = !mediaOpen"
      >
        <span
          class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-brand/10 text-n-blue-11"
        >
          <span class="i-lucide-images size-4" aria-hidden="true" />
        </span>
        <span>{{ t('CRM_KANBAN.RELATIONSHIP.MEDIA') }}</span>
        <span
          class="i-lucide-chevron-down ms-auto size-4 text-n-slate-11"
          :class="{ 'rotate-180': mediaOpen }"
          aria-hidden="true"
        />
      </button>
      <div
        v-if="mediaOpen"
        :id="`${id}-media`"
        class="min-w-0 border-t border-n-weak"
      >
        <div
          class="flex flex-wrap gap-1 px-4 pt-4"
          role="group"
          :aria-label="t('CRM_KANBAN.RELATIONSHIP.MEDIA_SOURCE')"
        >
          <Button
            sm
            :variant="mediaEntity === 'contact' ? 'faded' : 'ghost'"
            :aria-pressed="mediaEntity === 'contact'"
            :label="t('CRM_KANBAN.RELATIONSHIP.FIELDS_CONTACT')"
            @click="changeMediaEntity('contact')"
          />
          <Button
            v-if="hasCompany"
            sm
            :variant="mediaEntity === 'company' ? 'faded' : 'ghost'"
            :aria-pressed="mediaEntity === 'company'"
            :label="t('CRM_KANBAN.RELATIONSHIP.FIELDS_COMPANY')"
            @click="changeMediaEntity('company')"
          />
        </div>
        <RelationshipMedia
          :key="`${accountId}-${mediaEntity}-${mediaEntity === 'company' ? company.id : contact.id}`"
          :contact-id="mediaEntity === 'contact' ? contact.id : null"
          :company-id="mediaEntity === 'company' ? company.id : null"
          :expanded="expandedMedia"
          embedded
          @expand="expandedMedia = true"
          @collapse="expandedMedia = false"
        />
      </div>
    </section>
  </div>
</template>
