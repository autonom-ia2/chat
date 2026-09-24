<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  pipelineStages: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  expanded: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();

function emptyStep() {
  return {
    position: 0,
    delay_seconds: 0,
    action_type: 'create_follow_up',
    action_config: {
      title: '',
      description: '',
      follow_up_type: 'task',
      automation_mode: 'reminder_only',
    },
  };
}

function emptyDraft() {
  return {
    name: '',
    description: '',
    trigger_event: 'on_enter',
    enabled: true,
    steps: [emptyStep()],
  };
}

const automations = ref([]);
const isLoading = ref(false);
const editingId = ref(null);
const draft = reactive(emptyDraft());

const uiFlags = computed(() => store.getters['crmKanban/getUIFlags']);
const stageOptions = computed(() =>
  props.pipelineStages.filter(stage => stage.id)
);
const agentOptions = computed(() =>
  props.agents.map(agent => ({ id: agent.id, name: agent.name }))
);

const loadAutomations = async () => {
  if (!props.stage?.id) return;
  isLoading.value = true;
  try {
    automations.value = await store.dispatch(
      'crmKanban/fetchStageAutomations',
      props.stage.id
    );
  } catch {
    automations.value = [];
  } finally {
    isLoading.value = false;
  }
};

const resetDraft = () => {
  Object.assign(draft, emptyDraft());
  editingId.value = null;
};

const startCreate = () => {
  resetDraft();
  draft.name = t('CRM_KANBAN.STAGE_AUTOMATIONS.NEW_RULE_NAME', {
    stage: props.stage.name,
  });
  editingId.value = 'new';
};

const startEdit = automation => {
  editingId.value = automation.id;
  draft.name = automation.name;
  draft.description = automation.description || '';
  draft.trigger_event = automation.trigger_event;
  draft.enabled = automation.enabled;
  draft.steps = (automation.steps || []).map((step, index) => ({
    position: step.position ?? index,
    delay_seconds: step.delay_seconds || 0,
    action_type: step.action_type,
    action_config: { ...(step.action_config || {}) },
  }));
  if (draft.steps.length === 0) draft.steps = [emptyStep()];
};

const addStep = () => {
  draft.steps.push({
    ...emptyStep(),
    position: draft.steps.length,
  });
};

const removeStep = index => {
  if (draft.steps.length === 1) return;
  draft.steps.splice(index, 1);
};

const onActionTypeChange = step => {
  if (step.action_type === 'create_follow_up') {
    step.action_config = {
      title: '',
      description: '',
      follow_up_type: 'task',
      automation_mode: 'reminder_only',
    };
  } else if (step.action_type === 'assign_owner') {
    step.action_config = {
      owner_id: agentOptions.value[0]?.id || '',
      use_card_owner: false,
    };
  } else if (step.action_type === 'move_stage') {
    step.action_config = {
      target_stage_id: stageOptions.value[0]?.id || '',
    };
  }
};

const saveAutomation = async () => {
  if (!props.stage?.id || !draft.name.trim()) return;
  const payload = {
    id: editingId.value === 'new' ? null : editingId.value,
    name: draft.name.trim(),
    description: draft.description?.trim() || '',
    trigger_event: draft.trigger_event,
    enabled: draft.enabled,
    steps: draft.steps.map((step, index) => ({
      position: index,
      delay_seconds: Number(step.delay_seconds || 0),
      action_type: step.action_type,
      action_config: step.action_config || {},
    })),
  };

  const saved = await store.dispatch('crmKanban/saveStageAutomation', {
    stageId: props.stage.id,
    automation: payload,
  });
  const others = automations.value.filter(item => item.id !== saved.id);
  automations.value = [...others, saved].sort(
    (a, b) => (a.position || 0) - (b.position || 0)
  );
  resetDraft();
};

const deleteAutomation = async automation => {
  await store.dispatch('crmKanban/deleteStageAutomation', automation.id);
  automations.value = automations.value.filter(
    item => item.id !== automation.id
  );
  if (editingId.value === automation.id) resetDraft();
};

const triggerLabel = value =>
  value === 'on_exit'
    ? t('CRM_KANBAN.STAGE_AUTOMATIONS.TRIGGER_EXIT')
    : t('CRM_KANBAN.STAGE_AUTOMATIONS.TRIGGER_ENTER');

const actionLabel = value => {
  const map = {
    create_follow_up: t('CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_FOLLOW_UP'),
    assign_owner: t('CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_ASSIGN'),
    move_stage: t('CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_MOVE'),
  };
  return map[value] || value;
};

const triggerChoices = computed(() =>
  ['on_enter', 'on_exit'].map(value => ({ value, label: triggerLabel(value) }))
);
const actionChoices = computed(() =>
  ['create_follow_up', 'assign_owner', 'move_stage'].map(value => ({
    value,
    label: actionLabel(value),
  }))
);
const ownerChoices = computed(() =>
  agentOptions.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const targetStageChoices = computed(() =>
  stageOptions.value.map(stage => ({ value: stage.id, label: stage.name }))
);

watch(
  () => [props.expanded, props.stage?.id],
  () => {
    if (props.expanded && props.stage?.id) loadAutomations();
  },
  { immediate: true }
);
</script>

<template>
  <div class="grid gap-3 border-t border-n-weak pt-3">
    <div class="flex items-center justify-between gap-2">
      <div>
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.TITLE') }}
        </p>
        <p class="mb-0 text-xs leading-5 text-n-slate-10">
          {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.HELP') }}
        </p>
      </div>
      <Button
        :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.ADD_RULE')"
        icon="i-lucide-plus"
        slate
        faded
        xs
        :disabled="!stage.id"
        @click="startCreate"
      />
    </div>

    <div
      v-if="isLoading || uiFlags.isFetchingStageAutomations"
      class="rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-xs text-n-slate-11"
    >
      {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.LOADING') }}
    </div>

    <div
      v-else-if="automations.length === 0 && editingId !== 'new'"
      class="rounded-lg border border-dashed border-n-weak px-3 py-2 text-xs text-n-slate-10"
    >
      {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.EMPTY') }}
    </div>

    <div v-else class="grid gap-2">
      <div
        v-for="automation in automations"
        :key="automation.id"
        class="flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2"
      >
        <div class="min-w-0">
          <p class="mb-0 truncate text-xs font-medium text-n-slate-12">
            {{ automation.name }}
          </p>
          <p class="mb-0 truncate text-[11px] text-n-slate-10">
            {{
              t('CRM_KANBAN.STAGE_AUTOMATIONS.SUMMARY', {
                trigger: triggerLabel(automation.trigger_event),
                steps: t('CRM_KANBAN.STAGE_AUTOMATIONS.STEPS_COUNT', {
                  count: automation.steps?.length || 0,
                }),
              })
            }}
          </p>
        </div>
        <div class="flex shrink-0 items-center gap-1">
          <span
            class="rounded px-1.5 py-0.5 text-[10px]"
            :class="
              automation.enabled
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-10'
            "
          >
            {{
              automation.enabled
                ? t('CRM_KANBAN.STAGE_AUTOMATIONS.ENABLED')
                : t('CRM_KANBAN.STAGE_AUTOMATIONS.DISABLED')
            }}
          </span>
          <Button
            icon="i-lucide-pencil"
            slate
            ghost
            xs
            @click="startEdit(automation)"
          />
          <Button
            icon="i-lucide-trash-2"
            ruby
            ghost
            xs
            :is-loading="uiFlags.isDeletingStageAutomation"
            @click="deleteAutomation(automation)"
          />
        </div>
      </div>
    </div>

    <div
      v-if="editingId"
      class="grid gap-3 rounded-lg border border-n-brand/30 bg-n-alpha-black2 p-3"
    >
      <Input
        v-model="draft.name"
        :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.RULE_NAME')"
        :placeholder="t('CRM_KANBAN.STAGE_AUTOMATIONS.RULE_NAME_PLACEHOLDER')"
      />

      <div class="grid gap-3 md:grid-cols-2">
        <label class="grid gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.TRIGGER') }}
          </span>
          <ChoiceSelect
            v-model="draft.trigger_event"
            :options="triggerChoices"
            :aria-label="t('CRM_KANBAN.STAGE_AUTOMATIONS.TRIGGER')"
            class="w-full"
          />
        </label>
        <label class="flex items-end gap-2 pb-1 text-sm text-n-slate-12">
          <input
            v-model="draft.enabled"
            type="checkbox"
            class="h-4 w-4 rounded border-n-weak"
          />
          <span>{{ t('CRM_KANBAN.STAGE_AUTOMATIONS.ENABLED') }}</span>
        </label>
      </div>

      <div class="grid gap-2">
        <div class="flex items-center justify-between gap-2">
          <p class="mb-0 text-xs font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.SEQUENCE') }}
          </p>
          <Button
            :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.ADD_STEP')"
            icon="i-lucide-plus"
            slate
            faded
            xs
            @click="addStep"
          />
        </div>

        <div
          v-for="(step, index) in draft.steps"
          :key="index"
          class="grid gap-2 rounded-lg border border-n-weak p-2"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-medium text-n-slate-11">
              {{
                t('CRM_KANBAN.STAGE_AUTOMATIONS.STEP_LABEL', {
                  count: index + 1,
                })
              }}
            </span>
            <Button
              v-if="draft.steps.length > 1"
              icon="i-lucide-trash-2"
              ruby
              ghost
              xs
              @click="removeStep(index)"
            />
          </div>

          <div class="grid gap-2">
            <label class="grid min-w-0 gap-1">
              <span class="text-[11px] text-n-slate-10">
                {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.DELAY') }}
              </span>
              <input
                v-model.number="step.delay_seconds"
                type="number"
                min="0"
                class="reset-base !mb-0 h-9 w-full min-w-0 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm outline outline-1 outline-n-weak"
              />
            </label>
            <label class="grid min-w-0 gap-1">
              <span class="text-[11px] text-n-slate-10">
                {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.ACTION') }}
              </span>
              <ChoiceSelect
                v-model="step.action_type"
                :options="actionChoices"
                :aria-label="t('CRM_KANBAN.STAGE_AUTOMATIONS.ACTION')"
                class="w-full min-w-0"
                @change="onActionTypeChange(step)"
              />
            </label>
          </div>

          <template v-if="step.action_type === 'create_follow_up'">
            <Input
              v-model="step.action_config.title"
              :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.FOLLOW_UP_TITLE')"
            />
            <label class="grid gap-1">
              <span class="text-[11px] text-n-slate-10">
                {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.FOLLOW_UP_DESCRIPTION') }}
              </span>
              <textarea
                v-model="step.action_config.description"
                rows="2"
                class="reset-base rounded-lg border-0 bg-n-alpha-black2 px-3 py-2 text-sm outline outline-1 outline-n-weak"
              />
            </label>
          </template>

          <template v-else-if="step.action_type === 'assign_owner'">
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="step.action_config.use_card_owner"
                type="checkbox"
                class="h-4 w-4 rounded border-n-weak"
              />
              <span>{{
                t('CRM_KANBAN.STAGE_AUTOMATIONS.USE_CARD_OWNER')
              }}</span>
            </label>
            <label v-if="!step.action_config.use_card_owner" class="grid gap-1">
              <span class="text-[11px] text-n-slate-10">
                {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.OWNER') }}
              </span>
              <ChoiceSelect
                v-model="step.action_config.owner_id"
                :options="ownerChoices"
                :aria-label="t('CRM_KANBAN.STAGE_AUTOMATIONS.OWNER')"
              />
            </label>
          </template>

          <template v-else-if="step.action_type === 'move_stage'">
            <label class="grid gap-1">
              <span class="text-[11px] text-n-slate-10">
                {{ t('CRM_KANBAN.STAGE_AUTOMATIONS.TARGET_STAGE') }}
              </span>
              <ChoiceSelect
                v-model="step.action_config.target_stage_id"
                :options="targetStageChoices"
                :aria-label="t('CRM_KANBAN.STAGE_AUTOMATIONS.TARGET_STAGE')"
              />
            </label>
          </template>
        </div>
      </div>

      <div class="flex justify-end gap-2">
        <Button
          :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.CANCEL')"
          slate
          faded
          sm
          @click="resetDraft"
        />
        <Button
          :label="t('CRM_KANBAN.STAGE_AUTOMATIONS.SAVE')"
          icon="i-lucide-check"
          sm
          :is-loading="uiFlags.isSavingStageAutomation"
          :disabled="!draft.name.trim()"
          @click="saveAutomation"
        />
      </div>
    </div>
  </div>
</template>
