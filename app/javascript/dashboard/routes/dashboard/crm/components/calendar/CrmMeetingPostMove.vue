<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// Depois de "Aconteceu" (#1193, J4-A7). A página de agendamento diz para qual
// etapa o card vai: no modo "perguntar", pergunta com "Mover" e "Agora não";
// no automático, o servidor já moveu e aqui só avisa.
const props = defineProps({
  // { mode: 'ask'|'auto', moved, stage: { id, name } } do record_outcome.
  postMeeting: { type: Object, required: true },
  cardId: { type: [String, Number], required: true },
});

const emit = defineEmits(['moved']);
const { t } = useI18n();

const dismissed = ref(false);
const moving = ref(false);
const moved = ref(Boolean(props.postMeeting.moved));
const failed = ref(false);

const move = async () => {
  if (moving.value) return;
  moving.value = true;
  failed.value = false;
  try {
    await CrmKanbanAPI.moveCard(props.cardId, props.postMeeting.stage.id);
    moved.value = true;
    emit('moved', props.postMeeting.stage);
  } catch {
    failed.value = true;
  } finally {
    moving.value = false;
  }
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="!dismissed"
    data-test="meeting-post-move"
    :data-mode="postMeeting.mode"
    class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-3"
  >
    <p v-if="moved" role="status" class="mb-0 text-sm text-n-teal-11">
      {{
        t('CRM_KANBAN.CALENDAR.MEETING_DAY.MOVED', {
          stage: postMeeting.stage.name,
        })
      }}
    </p>
    <template v-else>
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{
          t('CRM_KANBAN.CALENDAR.MEETING_DAY.MOVE_QUESTION', {
            stage: postMeeting.stage.name,
          })
        }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.MOVE_HINT') }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          data-test="meeting-post-move-confirm"
          class="inline-flex min-h-11 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white hover:bg-n-brand/90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          :disabled="moving"
          :aria-busy="moving"
          @click="move"
        >
          <span class="i-lucide-arrow-right size-4" aria-hidden="true" />
          {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.MOVE') }}
        </button>
        <button
          type="button"
          data-test="meeting-post-move-dismiss"
          class="inline-flex min-h-11 items-center rounded-lg px-4 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-weak hover:bg-n-alpha-2 focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="dismissed = true"
        >
          {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.NOT_NOW') }}
        </button>
      </div>
      <p v-if="failed" role="alert" class="mb-0 text-xs text-n-ruby-11">
        {{ t('CRM_KANBAN.CALENDAR.MEETING_DAY.MOVE_FAILED') }}
      </p>
    </template>
  </section>
</template>
