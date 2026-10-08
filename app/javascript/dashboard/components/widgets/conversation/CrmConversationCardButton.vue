<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CrmConversationSubjects from 'dashboard/routes/dashboard/conversation/CrmConversationSubjects.vue';
import { useCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// Cabeçalho da conversa (#1143): o botão mostra o assunto atual e abre a lista de assuntos, onde se troca o atual
// ou se cria um novo. Card cujo título é só o nome do contato ainda não tem assunto: aí mostra a etapa.
const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { canViewCrm, canManageCards } = useCrmPermissions();

const isOpen = ref(false);
const conversationId = computed(() => props.chat?.id);
const stage = useCrmConversationStage(conversationId);

const accountId = computed(() => store.getters.getCurrentAccountId);
const globalConfig = computed(() => store.getters['globalConfig/get'] || {});
const isEnabled = computed(
  () =>
    (globalConfig.value.crmKanbanEnabled === true ||
      window.globalConfig?.CRM_KANBAN_ENABLED === 'true') &&
    canViewCrm.value
);

const subjectTitle = computed(() => {
  const title = String(stage.value?.title || '').trim();
  const sender = props.chat?.meta?.sender || {};
  if (!title || [sender.name, sender.phone_number].includes(title)) return '';
  return title;
});

const buttonLabel = computed(
  () =>
    subjectTitle.value ||
    stage.value?.stage_name ||
    t('CRM_KANBAN.CONVERSATION.TITLE')
);

const otherSubjects = computed(() =>
  Math.max((stage.value?.subjects_count || 0) - 1, 0)
);

const togglePanel = () => {
  isOpen.value = !isOpen.value;
};

const openCrm = () => {
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: accountId.value },
  });
};
</script>

<template>
  <div v-show="isEnabled" class="relative">
    <NextButton
      icon="i-lucide-kanban"
      :label="buttonLabel"
      slate
      faded
      sm
      class="max-w-[16rem]"
      :title="t('CRM_KANBAN.CONVERSATION.SUBJECTS.CURRENT_HINT')"
      :aria-expanded="isOpen ? 'true' : 'false'"
      @click="togglePanel"
    >
      <template v-if="otherSubjects" #default>
        <span class="truncate">{{ buttonLabel }}</span>
        <span
          class="rounded-full bg-n-alpha-2 px-1.5 text-[11px] font-semibold text-n-slate-11"
        >
          {{
            t('CRM_KANBAN.CONVERSATION.SUBJECTS.MORE', { count: otherSubjects })
          }}
        </span>
      </template>
    </NextButton>
    <div
      v-if="isOpen"
      class="absolute right-0 top-10 z-50 w-80 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-lg"
    >
      <div class="mb-3 flex items-start justify-between gap-3">
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.LABEL') }}
        </p>
        <NextButton
          icon="i-lucide-external-link"
          xs
          ghost
          slate
          :title="t('CRM_KANBAN.CONVERSATION.OPEN_CRM')"
          @click="openCrm"
        />
      </div>
      <CrmConversationSubjects
        v-if="conversationId"
        :conversation-id="conversationId"
        :can-manage="canManageCards"
      />
    </div>
  </div>
</template>
