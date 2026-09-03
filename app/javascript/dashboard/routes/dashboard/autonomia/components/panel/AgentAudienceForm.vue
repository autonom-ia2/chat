<script setup>
import { ref, computed, watch, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import AgentAudienceGroup from './audience/AgentAudienceGroup.vue';
import { useAgentAudienceFilterTypes } from './audience/useAgentAudienceFilterTypes.js';

// #284 (Entrega 2a) — "Público-alvo": everyone (audience null) or a condition tree.
// Emits `{ audience, audienceUnknownContact }`: the serialized tree (or null) plus
// what to do with a conversation that has no contact yet (respond | handoff). The
// host saves both under `config` (audience / audience_unknown_contact).
const props = defineProps({
  agent: { type: Object, default: () => ({}) },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { filterTypes } = useAgentAudienceFilterTypes();

const MODE = { EVERYONE: 'everyone', SPECIFIC: 'specific' };
const UNKNOWN_CONTACT = { RESPOND: 'respond', HANDOFF: 'handoff' };

const UNKNOWN_CONTACT_OPTIONS = computed(() =>
  Object.values(UNKNOWN_CONTACT).map(value => ({
    value,
    label: t(`AGENTS.AUDIENCE.UNKNOWN_CONTACT.${value.toUpperCase()}`),
  }))
);

let uid = 0;
const nextId = () => {
  uid += 1;
  return `agent-audience-root-${uid}`;
};

const hasConditions = node =>
  node && Object.prototype.hasOwnProperty.call(node, 'conditions');

const defaultRoot = () => ({ id: nextId(), operator: 'and', conditions: [] });

const root = ref(defaultRoot());
const mode = ref(MODE.EVERYONE);
const unknownContact = ref(UNKNOWN_CONTACT.RESPOND);
const showEmptyAudienceError = ref(false);

// The policy only matters once there is a condition the gate can't check
// without a contact; hide it otherwise so "everyone" stays a single choice.
const showUnknownContact = computed(
  () => mode.value === MODE.SPECIFIC && root.value.conditions.length > 0
);

const findOption = (filterType, value) =>
  filterType?.options?.find(option => String(option.id) === String(value));

const hydrateValues = (leaf, filterType) => {
  const raw = Array.isArray(leaf.values) ? leaf.values : [leaf.values];
  const inputType = filterType?.inputType;
  if (inputType === 'multiSelect') {
    return raw.map(
      value => findOption(filterType, value) ?? { id: value, name: value }
    );
  }
  if (['searchSelect', 'booleanSelect'].includes(inputType)) {
    return findOption(filterType, raw[0]) ?? { id: raw[0], name: raw[0] };
  }
  return raw[0] ?? '';
};

const hydrateNode = node => {
  if (hasConditions(node)) {
    return {
      id: nextId(),
      operator: node.operator || 'and',
      conditions: (node.conditions || []).map(hydrateNode),
    };
  }
  const filterType = filterTypes.value.find(
    type => type.attributeKey === node.attribute_key
  );
  return {
    id: nextId(),
    attributeKey: node.attribute_key,
    filterOperator: node.filter_operator,
    values: hydrateValues(node, filterType),
    attributeModel: filterType?.attributeModel || 'standard',
  };
};

const hydrateRoot = audience => {
  if (!audience) return defaultRoot();
  const hydrated = hydrateNode(audience);
  return hasConditions(hydrated)
    ? hydrated
    : { id: nextId(), operator: 'and', conditions: [hydrated] };
};

const serializeValues = values => {
  if (Array.isArray(values)) {
    return values[0]?.id ? values.map(value => value.id) : values;
  }
  if (values && typeof values === 'object') return [values.id];
  if (values === '' || values === null || values === undefined) return [];
  return [values];
};

const serializeNode = node => {
  if (hasConditions(node)) {
    return {
      operator: node.operator,
      conditions: node.conditions.map(serializeNode),
    };
  }
  return {
    attribute_key: node.attributeKey,
    filter_operator: node.filterOperator,
    values: serializeValues(node.values),
  };
};

const groupRef = useTemplateRef('groupRef');

const handleSubmit = () => {
  const isSpecific = mode.value === MODE.SPECIFIC;
  if (isSpecific && !root.value.conditions.length) {
    showEmptyAudienceError.value = true;
    return;
  }
  showEmptyAudienceError.value = false;
  if (isSpecific && groupRef.value && !groupRef.value.validate()) return;

  emit('submit', {
    audience: isSpecific ? serializeNode(root.value) : null,
    audienceUnknownContact: unknownContact.value,
  });
};

watch(
  () => props.agent,
  agent => {
    if (!agent) return;
    const audience = agent.config?.audience;
    root.value = hydrateRoot(audience);
    mode.value = audience ? MODE.SPECIFIC : MODE.EVERYONE;
    unknownContact.value =
      agent.config?.audience_unknown_contact || UNKNOWN_CONTACT.RESPOND;
  },
  { immediate: true }
);

watch(
  () => root.value.conditions.length,
  () => {
    showEmptyAudienceError.value = false;
  }
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-3">
      <RadioCard
        :id="MODE.EVERYONE"
        :label="t('AGENTS.AUDIENCE.EVERYONE.LABEL')"
        :description="t('AGENTS.AUDIENCE.EVERYONE.DESC')"
        :is-active="mode === MODE.EVERYONE"
        @select="mode = MODE.EVERYONE"
      />
      <RadioCard
        :id="MODE.SPECIFIC"
        :label="t('AGENTS.AUDIENCE.SPECIFIC.LABEL')"
        :description="t('AGENTS.AUDIENCE.SPECIFIC.DESC')"
        :is-active="mode === MODE.SPECIFIC"
        @select="mode = MODE.SPECIFIC"
      >
        <AgentAudienceGroup
          v-if="mode === MODE.SPECIFIC"
          ref="groupRef"
          v-model="root"
          is-root
          class="w-full mt-2"
          :filter-types="filterTypes"
        />
        <p v-if="showEmptyAudienceError" class="mt-2 text-sm text-n-ruby-11">
          {{ t('AGENTS.AUDIENCE.EMPTY_ERROR') }}
        </p>
      </RadioCard>
    </div>
    <div v-if="showUnknownContact" class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.AUDIENCE.UNKNOWN_CONTACT.LABEL') }}
      </label>
      <Select
        v-model="unknownContact"
        :options="UNKNOWN_CONTACT_OPTIONS"
        class="w-full"
      />
      <p class="m-0 text-xs text-n-slate-10">
        {{ t('AGENTS.AUDIENCE.UNKNOWN_CONTACT.HINT') }}
      </p>
    </div>
    <NextButton
      solid
      sm
      :label="t('AGENTS.AUDIENCE.SAVE')"
      :is-loading="isSaving"
      :disabled="isSaving"
      class="w-fit"
      @click="handleSubmit"
    />
  </div>
</template>
