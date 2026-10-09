<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BuilderKnowledgePanel from '../../components/builder/BuilderKnowledgePanel.vue';

const props = defineProps({
  agentId: { type: [String, Number], default: null },
  reusableSources: { type: Array, default: () => [] },
  reusableSourcesLoaded: { type: Boolean, default: false },
  reusableSourcesLoading: { type: Boolean, default: false },
  reusableSourcesError: { type: Boolean, default: false },
  isCopying: { type: Boolean, default: false },
});

const emit = defineEmits(['copy']);
const { t } = useI18n();
const reusableDialog = ref(null);
const singleSource = computed(() =>
  props.reusableSources.length === 1 ? props.reusableSources[0] : null
);
const sourceLabel = source =>
  source?.reference || source?.title || source?.agent_name || source?.agentName;
const singleSourceLabel = computed(() => sourceLabel(singleSource.value));

const openReusableDialog = () => reusableDialog.value?.open();
const copySource = sourceId => {
  emit('copy', sourceId);
  reusableDialog.value?.close();
};
</script>

<template>
  <section class="flex flex-col gap-4">
    <BuilderKnowledgePanel :agent-id="agentId" confirm-removal knowledge-only />

    <div
      v-if="reusableSourcesLoading"
      class="flex items-center gap-2 p-4 text-xs rounded-2xl bg-n-alpha-1 text-n-slate-11"
      role="status"
    >
      <i
        class="i-lucide-loader-circle size-4 animate-spin"
        aria-hidden="true"
      />
      {{ t('AGENTS.CREATION.tell.reusableLoading') }}
    </div>

    <section
      v-else-if="reusableSourcesLoaded"
      class="flex flex-col gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
      :aria-label="t('AGENTS.CREATION.tell.reusableTitle')"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.tell.reusableTitle') }}
          </h2>
          <p class="mt-1 text-xs leading-5 text-n-slate-11">
            {{ t('AGENTS.CREATION.tell.reusableDescription') }}
          </p>
        </div>
        <NextButton
          v-if="reusableSources.length > 1"
          ghost
          slate
          class="min-h-11 shrink-0"
          :label="t('AGENTS.CREATION.actions.chooseMaterial')"
          @click="openReusableDialog"
        />
      </div>
      <template v-if="singleSource">
        <p class="text-xs text-n-slate-11">
          {{
            t('AGENTS.CREATION.tell.reusableSingle', {
              material: singleSourceLabel,
            })
          }}
        </p>
        <NextButton
          ghost
          slate
          class="min-h-11 self-start"
          :label="t('AGENTS.CREATION.actions.useMaterial')"
          :is-loading="isCopying"
          @click="copySource(singleSource.id)"
        />
      </template>
      <p v-else-if="!reusableSources.length" class="text-xs text-n-slate-11">
        {{
          reusableSourcesError
            ? t('AGENTS.CREATION.tell.reusableError')
            : t('AGENTS.CREATION.tell.reusableEmpty')
        }}
      </p>
    </section>

    <Dialog
      ref="reusableDialog"
      :title="t('AGENTS.CREATION.tell.reusableTitle')"
      :description="t('AGENTS.CREATION.tell.reusableDescription')"
      :show-confirm-button="false"
      :cancel-button-label="t('AGENTS.CREATION.actions.cancel')"
    >
      <ul class="flex flex-col gap-2" role="list">
        <li
          v-for="source in reusableSources"
          :key="source.id"
          class="flex items-center justify-between gap-3 px-3 py-2 rounded-xl bg-n-alpha-1"
        >
          <span class="min-w-0 text-xs text-n-slate-12">
            {{ sourceLabel(source) }}
          </span>
          <NextButton
            ghost
            slate
            class="min-h-11 shrink-0"
            :label="t('AGENTS.CREATION.actions.useMaterial')"
            :is-loading="isCopying"
            @click="copySource(source.id)"
          />
        </li>
      </ul>
    </Dialog>
  </section>
</template>
