<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';

// Decisão "a" do Rodrigo (#1606, 15/10): o assunto mudou depois que uma PESSOA recebeu a conversa, e ela não cuida do
// funil novo. A conversa fica com ela; a tela só sugere passar para a equipe do assunto novo. Só quem está com a
// conversa vê. Nada é repassado sozinho.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  assigneeId: { type: Number, default: null },
});

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

const repasse = ref(null);
const answering = ref(false);
// Decisão 2a (#1606): ninguém da equipe nova online. Antes de passar, a pessoa vê que a conversa vai esperar.
const confirming = ref(false);

const isMine = computed(
  () => Boolean(props.assigneeId) && props.assigneeId === currentUser.value?.id
);
const isVisible = computed(() => isMine.value && Boolean(repasse.value));
const pipeline = computed(() => repasse.value?.pipeline_name || '');
const message = computed(() =>
  confirming.value
    ? t('CRM_KANBAN.CONVERSATION.REPASSE.NOBODY_ONLINE', {
        pipeline: pipeline.value,
      })
    : t('CRM_KANBAN.CONVERSATION.REPASSE.TEXT', { pipeline: pipeline.value })
);
const passLabel = computed(() =>
  confirming.value
    ? t('CRM_KANBAN.CONVERSATION.REPASSE.PASS_ANYWAY')
    : t('CRM_KANBAN.CONVERSATION.REPASSE.PASS', { pipeline: pipeline.value })
);

let lastRequest = 0;
const fetchRepasse = async () => {
  if (!isMine.value) {
    repasse.value = null;
    return;
  }
  lastRequest += 1;
  const requestId = lastRequest;
  try {
    const { data } = await CrmKanbanAPI.getConversationSubjects(
      props.conversationId
    );
    if (requestId === lastRequest) repasse.value = data?.repasse || null;
  } catch {
    if (requestId === lastRequest) repasse.value = null;
  }
};

const answer = async pass => {
  if (!repasse.value || answering.value) return;
  if (pass && repasse.value.equipe_online === false && !confirming.value) {
    confirming.value = true;
    return;
  }
  answering.value = true;
  const { card_id: cardId } = repasse.value;
  const name = pipeline.value;
  try {
    if (pass) {
      await CrmKanbanAPI.passSubjectToTeam(props.conversationId, cardId);
      useAlert(t('CRM_KANBAN.CONVERSATION.REPASSE.DONE', { pipeline: name }));
    } else {
      await CrmKanbanAPI.keepSubjectWithMe(props.conversationId, cardId);
    }
    repasse.value = null;
    confirming.value = false;
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.REPASSE.ERROR'));
  } finally {
    answering.value = false;
    notifyCrmSubjectsChanged(props.conversationId);
  }
};

watch(
  () => crmSubjectsChange.value,
  change => {
    if (String(change.conversationId) === String(props.conversationId)) {
      fetchRepasse();
    }
  }
);

watch(
  () => [props.conversationId, isMine.value],
  () => {
    repasse.value = null;
    confirming.value = false;
    fetchRepasse();
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="isVisible"
    class="mx-4 mb-2 grid gap-2 rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2.5"
    data-crm-repasse-do-assunto
  >
    <p
      class="mb-0 flex items-start gap-2 text-sm leading-5 text-n-slate-12"
      role="status"
      :data-crm-repasse-nobody-online="confirming || undefined"
    >
      <span
        class="mt-0.5 size-4 shrink-0 text-n-amber-11"
        :class="confirming ? 'i-lucide-clock' : 'i-lucide-arrow-right-left'"
      />
      <span>{{ message }}</span>
    </p>
    <div class="flex flex-wrap gap-2">
      <NextButton
        :label="passLabel"
        sm
        class="min-h-11"
        :is-loading="answering"
        :disabled="answering"
        data-crm-repasse-pass
        @click="answer(true)"
      />
      <NextButton
        :label="t('CRM_KANBAN.CONVERSATION.REPASSE.KEEP')"
        sm
        slate
        faded
        class="min-h-11"
        :disabled="answering"
        data-crm-repasse-keep
        @click="answer(false)"
      />
    </div>
  </div>
</template>
