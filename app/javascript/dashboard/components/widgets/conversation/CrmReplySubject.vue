<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';

// "Este envio fica no assunto" (#1143): com mais de um assunto aberto na conversa, a caixa de resposta mostra em
// qual deles a mensagem vai entrar. Escolher outro torna esse o assunto atual na hora (o mesmo que clicar no
// painel). O id escolhido segue no envio; com um assunto só, nada aparece e nada muda.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const cardId = defineModel('cardId', { type: Number, default: null });

const { t } = useI18n();
const { canViewCrm, canManageCards } = useCrmPermissions();

const subjects = ref([]);
const isOpen = ref(false);
const isSwitching = ref(false);

const openSubjects = computed(() =>
  subjects.value.filter(subject => subject.status === 'open')
);
const current = computed(() => openSubjects.value.find(s => s.current));
const isVisible = computed(
  () => canViewCrm.value && openSubjects.value.length > 1
);

let lastRequest = 0;
const fetchSubjects = async () => {
  lastRequest += 1;
  const requestId = lastRequest;
  try {
    const { data } = await CrmKanbanAPI.getConversationSubjects(
      props.conversationId
    );
    if (requestId !== lastRequest) return;
    subjects.value = data?.payload || [];
  } catch {
    if (requestId === lastRequest) subjects.value = [];
  }
};

watch(
  [isVisible, current],
  () => {
    cardId.value = isVisible.value ? current.value?.id || null : null;
  },
  { immediate: true }
);

const choose = async subject => {
  isOpen.value = false;
  if (!canManageCards.value || subject.current || isSwitching.value) return;
  isSwitching.value = true;
  try {
    await CrmKanbanAPI.focusConversationSubject(
      props.conversationId,
      subject.id
    );
    notifyCrmSubjectsChanged(props.conversationId);
  } catch {
    useAlert(t('CRM_KANBAN.CONVERSATION.SUBJECTS.SWITCH_ERROR'));
  } finally {
    isSwitching.value = false;
  }
};

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
    isOpen.value = false;
    fetchSubjects();
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="isVisible && current"
    class="relative flex items-center gap-1.5 px-4 pt-2 text-xs text-n-slate-11"
    data-crm-reply-subject
  >
    <span class="i-lucide-corner-down-right size-3.5 shrink-0" />
    <span>{{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.REPLY_IN') }}</span>
    <button
      type="button"
      class="flex min-h-7 min-w-0 items-center gap-1 rounded-md bg-n-blue-2 px-2 font-medium text-n-blue-11 transition hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-expanded="isOpen ? 'true' : 'false'"
      :disabled="!canManageCards || isSwitching"
      @click="isOpen = !isOpen"
    >
      <span class="truncate">{{ current.title }}</span>
      <span
        v-if="canManageCards"
        class="i-lucide-chevron-down size-3.5 shrink-0"
        aria-hidden="true"
      />
    </button>
    <ul
      v-if="isOpen"
      class="absolute bottom-full left-4 z-50 mb-1 grid w-72 list-none gap-0.5 rounded-lg border border-n-weak bg-n-solid-1 p-1 shadow-lg"
    >
      <li v-for="subject in openSubjects" :key="subject.id">
        <button
          type="button"
          class="flex min-h-11 w-full flex-col items-start rounded-md px-2.5 py-1.5 text-start hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-current="subject.current ? 'true' : undefined"
          @click="choose(subject)"
        >
          <span class="w-full truncate text-sm text-n-slate-12">
            {{ subject.title }}
          </span>
          <span class="w-full truncate text-xs text-n-slate-11">
            {{ subject.pipeline_name }} · {{ subject.stage_name }}
          </span>
        </button>
      </li>
    </ul>
  </div>
</template>
