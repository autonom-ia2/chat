<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  CLOSED_STATUSES,
  cardStatusLabel,
} from 'dashboard/routes/dashboard/crm/helpers/cardOutcome';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import CrmNewSubjectDialog from './CrmNewSubjectDialog.vue';

// Assuntos da conversa (#1143): cada card dela numa linha, o assunto atual marcado. Clicar num assunto aberto faz
// dele o atual; "Novo assunto" abre o diálogo. Sem permissão de editar cards, a lista só informa.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  canManage: { type: Boolean, default: false },
});

const STAGE_FALLBACK_COLOR = '#64748b';

const { t } = useI18n();

const subjects = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const switchingId = ref(null);
const dialogRef = ref(null);

const hasSubjects = computed(() => subjects.value.length > 0);

// Troca rápida de conversa: só a resposta da conversa aberta agora vale.
let lastRequest = 0;
const fetchSubjects = async () => {
  if (!props.conversationId) return;
  lastRequest += 1;
  const requestId = lastRequest;
  const requestedFor = props.conversationId;
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await CrmKanbanAPI.getConversationSubjects(requestedFor);
    if (requestId !== lastRequest) return;
    subjects.value = data?.payload || [];
  } catch {
    if (requestId === lastRequest) hasError.value = true;
  } finally {
    if (requestId === lastRequest) isLoading.value = false;
  }
};

const afterChange = () => notifyCrmSubjectsChanged(props.conversationId);

const canSwitch = subject =>
  props.canManage &&
  subject.status === 'open' &&
  !subject.current &&
  !switchingId.value;

const makeCurrent = async subject => {
  if (!canSwitch(subject)) return;
  switchingId.value = subject.id;
  try {
    await CrmKanbanAPI.focusConversationSubject(
      props.conversationId,
      subject.id
    );
    useAlert(
      t('CRM_KANBAN.CONVERSATION.SUBJECTS.SWITCHED', { title: subject.title })
    );
    await afterChange();
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.SUBJECTS.SWITCH_ERROR'));
  } finally {
    switchingId.value = null;
  }
};

const statusLabel = subject => {
  if (!CLOSED_STATUSES.includes(subject.status)) return '';
  return cardStatusLabel(t, subject.status, {
    metadata: { outcome_labels: subject.outcome_labels },
  });
};

const openNewSubject = () => dialogRef.value?.open();

watch(
  () => crmSubjectsChange.value,
  change => {
    if (String(change.conversationId) === String(props.conversationId)) {
      fetchSubjects();
    }
  }
);

watch(
  () => props.conversationId,
  () => {
    subjects.value = [];
    fetchSubjects();
  },
  { immediate: true }
);
</script>

<template>
  <div class="grid gap-2" data-crm-conversation-subjects>
    <div class="flex items-center justify-between gap-2">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.LABEL') }}
      </span>
      <NextButton
        v-if="canManage"
        :label="t('CRM_KANBAN.CONVERSATION.SUBJECTS.NEW')"
        icon="i-lucide-plus"
        xs
        slate
        faded
        @click="openNewSubject"
      />
    </div>

    <p
      v-if="isLoading && !hasSubjects"
      class="mb-0 text-xs leading-5 text-n-slate-11"
    >
      {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.LOADING') }}
    </p>
    <div
      v-else-if="hasError"
      class="flex items-center justify-between gap-2 text-xs leading-5 text-n-slate-11"
    >
      <span>{{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.LOAD_ERROR') }}</span>
      <NextButton
        :label="t('CRM_KANBAN.CONVERSATION.SUBJECTS.RETRY')"
        xs
        link
        @click="fetchSubjects"
      />
    </div>
    <p v-else-if="!hasSubjects" class="mb-0 text-xs leading-5 text-n-slate-11">
      {{
        canManage
          ? t('CRM_KANBAN.CONVERSATION.SUBJECTS.EMPTY')
          : t('CRM_KANBAN.CONVERSATION.STAGE_BADGE_EMPTY')
      }}
    </p>

    <ul v-else class="mb-0 grid list-none gap-1.5 p-0">
      <li v-for="subject in subjects" :key="subject.id">
        <component
          :is="canSwitch(subject) ? 'button' : 'div'"
          :type="canSwitch(subject) ? 'button' : undefined"
          class="flex min-h-11 w-full items-start gap-2 rounded-lg border px-2.5 py-2 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="[
            subject.current
              ? 'border-n-blue-7 bg-n-blue-2'
              : 'border-n-weak bg-n-alpha-black2',
            canSwitch(subject) ? 'hover:border-n-strong' : '',
            subject.status === 'open' ? '' : 'opacity-70',
          ]"
          :aria-current="subject.current ? 'true' : undefined"
          data-crm-subject
          @click="makeCurrent(subject)"
        >
          <span
            class="mt-1.5 size-2.5 shrink-0 rounded-full ring-1 ring-inset ring-n-strong"
            :style="{
              backgroundColor: subject.stage_color || STAGE_FALLBACK_COLOR,
            }"
          />
          <span class="flex min-w-0 flex-1 flex-col">
            <span
              class="truncate text-sm font-medium leading-5 text-n-slate-12"
            >
              {{ subject.title }}
            </span>
            <span class="truncate text-xs leading-5 text-n-slate-11">
              {{
                t('CRM_KANBAN.CONVERSATION.SUBJECTS.PIPELINE_STAGE', {
                  pipeline: subject.pipeline_name,
                  stage: subject.stage_name,
                })
              }}
            </span>
            <span
              v-if="subject.owner"
              class="truncate text-xs leading-5 text-n-slate-11"
            >
              {{ subject.owner.name }}
            </span>
            <span v-if="canSwitch(subject)" class="sr-only">
              {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.MAKE_CURRENT_HINT') }}
            </span>
          </span>
          <span
            v-if="subject.current"
            class="shrink-0 rounded-full bg-n-brand px-2 py-0.5 text-[11px] font-semibold leading-4 text-white"
          >
            {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.CURRENT') }}
          </span>
          <span
            v-else-if="statusLabel(subject)"
            class="shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-semibold leading-4 text-n-slate-11"
          >
            {{ statusLabel(subject) }}
          </span>
        </component>
      </li>
    </ul>

    <CrmNewSubjectDialog
      ref="dialogRef"
      :conversation-id="conversationId"
      @created="afterChange"
    />
  </div>
</template>
