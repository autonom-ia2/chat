<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';

// "Este envio fica no assunto" (#1143): com mais de um assunto aberto na conversa, a caixa de resposta mostra em
// qual deles a mensagem vai entrar. Escolher outro torna esse o assunto atual (o mesmo que clicar no painel) e já
// vale para o próximo envio, sem esperar a lista recarregar. Com um assunto só, nada aparece e nada muda.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const cardId = defineModel('cardId', { type: Number, default: null });

const { t } = useI18n();
const { canViewCrm, canManageCards } = useCrmPermissions();

const menuId = useId();
const subjects = ref([]);
const isOpen = ref(false);
const isSwitching = ref(false);
const toggleRef = ref(null);
const menuRef = ref(null);

const openSubjects = computed(() =>
  subjects.value.filter(subject => subject.status === 'open')
);
const current = computed(() => openSubjects.value.find(s => s.current));
const isVisible = computed(
  () => canViewCrm.value && openSubjects.value.length > 1
);
const chosen = computed(
  () =>
    openSubjects.value.find(subject => subject.id === cardId.value) ||
    current.value
);

let lastRequest = 0;
const fetchSubjects = async () => {
  if (!canViewCrm.value) return;
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
    if (!isVisible.value) isOpen.value = false;
  },
  { immediate: true }
);

const closeMenu = ({ returnFocus = false } = {}) => {
  isOpen.value = false;
  if (returnFocus) toggleRef.value?.focus();
};

const toggleMenu = async () => {
  if (!canManageCards.value) return;
  if (isOpen.value) {
    closeMenu();
    return;
  }
  isOpen.value = true;
  fetchSubjects();
  await nextTick();
  menuRef.value?.querySelector('button')?.focus();
};

const choose = async subject => {
  closeMenu({ returnFocus: true });
  if (!canManageCards.value || isSwitching.value) return;
  if (subject.id === chosen.value?.id) return;

  const previous = cardId.value;
  cardId.value = subject.id;
  isSwitching.value = true;
  try {
    await CrmKanbanAPI.focusConversationSubject(
      props.conversationId,
      subject.id
    );
    notifyCrmSubjectsChanged(props.conversationId);
  } catch {
    cardId.value = previous;
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
    closeMenu();
    fetchSubjects();
  },
  { immediate: true }
);
</script>

<template>
  <div class="contents">
    <OnClickOutside
      v-if="isVisible && chosen"
      class="relative flex items-center gap-1.5 px-4 pt-2 text-xs text-n-slate-11"
      data-crm-reply-subject
      @trigger="closeMenu()"
      @keydown.esc.stop="closeMenu({ returnFocus: true })"
    >
      <span class="i-lucide-corner-down-right size-3.5 shrink-0" />
      <span>{{ t('CRM_KANBAN.CONVERSATION.SUBJECTS.REPLY_IN') }}</span>
      <button
        ref="toggleRef"
        type="button"
        class="relative flex min-h-7 min-w-0 items-center gap-1 rounded-md bg-n-blue-2 px-2 font-medium text-n-blue-11 transition after:absolute after:-inset-y-2 after:inset-x-0 after:content-[''] hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="{ 'cursor-default': !canManageCards }"
        :aria-haspopup="canManageCards ? 'menu' : undefined"
        :aria-expanded="
          canManageCards ? (isOpen ? 'true' : 'false') : undefined
        "
        :aria-controls="canManageCards ? menuId : undefined"
        :aria-busy="isSwitching ? 'true' : undefined"
        data-crm-reply-subject-toggle
        @click="toggleMenu"
      >
        <span class="truncate">{{ chosen.title }}</span>
        <span
          v-if="canManageCards"
          class="i-lucide-chevron-down size-3.5 shrink-0"
          aria-hidden="true"
        />
      </button>
      <ul
        v-if="isOpen"
        :id="menuId"
        ref="menuRef"
        role="menu"
        class="absolute bottom-full left-4 z-50 mb-1 grid w-72 list-none gap-0.5 rounded-lg border border-n-weak bg-n-solid-1 p-1 shadow-lg"
      >
        <li v-for="subject in openSubjects" :key="subject.id" role="none">
          <button
            type="button"
            role="menuitemradio"
            :aria-checked="subject.id === chosen.id ? 'true' : 'false'"
            class="flex min-h-11 w-full flex-col items-start rounded-md px-2.5 py-1.5 text-start hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="choose(subject)"
          >
            <span class="w-full truncate text-sm text-n-slate-12">
              {{ subject.title }}
            </span>
            <span class="w-full truncate text-xs text-n-slate-11">
              {{
                t('CRM_KANBAN.CONVERSATION.SUBJECTS.PIPELINE_STAGE', {
                  pipeline: subject.pipeline_name,
                  stage: subject.stage_name,
                })
              }}
            </span>
          </button>
        </li>
      </ul>
    </OnClickOutside>
  </div>
</template>
