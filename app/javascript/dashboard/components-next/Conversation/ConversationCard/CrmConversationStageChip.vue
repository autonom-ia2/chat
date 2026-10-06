<script setup>
import { computed, toRef } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const STAGE_FALLBACK_COLOR = '#64748b';

const route = useRoute();
const router = useRouter();
const stage = useCrmConversationStage(toRef(props, 'conversationId'));

const dotStyle = computed(() => ({
  backgroundColor: stage.value?.stage_color || STAGE_FALLBACK_COLOR,
}));

const label = computed(() => {
  if (!stage.value?.stage_name) return '';
  return stage.value.multiple_pipelines && stage.value.pipeline_name
    ? `${stage.value.pipeline_name} · ${stage.value.stage_name}`
    : stage.value.stage_name;
});

// O selo abre o card no CRM (a ficha já aberta, no funil certo). O clique não
// chega ao cartão da conversa, que abriria a conversa junto.
const abrirNoCrm = () => {
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: route.params.accountId },
    query: { card_id: stage.value.card_id },
  });
};
</script>

<template>
  <button
    v-if="label && stage.card_id"
    type="button"
    data-crm-stage-chip
    :title="$t('CRM_KANBAN.STAGE_CHIP_OPEN', { etapa: label })"
    :aria-label="$t('CRM_KANBAN.STAGE_CHIP_OPEN', { etapa: label })"
    class="relative flex flex-shrink-0 items-center gap-1 rounded-md border border-n-weak bg-n-alpha-1 px-1.5 py-0.5 transition after:absolute after:-inset-x-1 after:-inset-y-3 after:content-[''] hover:border-n-blue-7 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click.stop.prevent="abrirNoCrm"
  >
    <span class="size-1.5 flex-shrink-0 rounded-full" :style="dotStyle" />
    <span class="max-w-[13rem] truncate text-xs text-n-slate-11">{{
      label
    }}</span>
  </button>
  <div
    v-else-if="label"
    data-crm-stage-chip
    :title="label"
    class="flex flex-shrink-0 items-center gap-1 rounded-md border border-n-weak bg-n-alpha-1 px-1.5 py-0.5"
  >
    <span class="size-1.5 flex-shrink-0 rounded-full" :style="dotStyle" />
    <span class="max-w-[13rem] truncate text-xs text-n-slate-11">{{
      label
    }}</span>
  </div>
</template>
