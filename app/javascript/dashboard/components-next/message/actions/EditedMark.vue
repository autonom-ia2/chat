<script setup>
// O selo "editada" (chat#1709, fase 3): a mensagem foi editada pelo cliente no WhatsApp, pelo celular da empresa ou por
// um atendente no painel. O selo é um botão (teclado, leitor de tela e toque, alvo de 44 px) que abre logo abaixo os
// textos anteriores, cada um com quem editou. O histórico fica em `content_attributes.edit_history`.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  history: { type: Array, default: () => [] },
  currentUserId: { type: Number, default: null },
});

const { t } = useI18n();
const isOpen = ref(false);
const listId = useId();

const authorOf = entry => {
  if (entry.by === 'contact') return t('MESSAGE_ACTIONS.EDITED_BY_CONTACT');
  if (entry.by === 'phone') return t('MESSAGE_ACTIONS.EDITED_BY_PHONE');
  if (props.currentUserId != null && entry.userId === props.currentUserId) {
    return t('MESSAGE_ACTIONS.EDITED_BY_YOU');
  }
  return t('MESSAGE_ACTIONS.EDITED_BY_AGENT');
};

const entries = computed(() =>
  (Array.isArray(props.history) ? props.history : [])
    .filter(entry => typeof entry?.content === 'string' && entry.content)
    .map((entry, index) => ({
      key: `${entry.editedAt ?? ''}-${index}`,
      content: entry.content,
      author: authorOf(entry),
    }))
);
</script>

<template>
  <div data-edited-mark class="flex flex-col gap-1">
    <button
      type="button"
      class="inline-flex items-center gap-1 px-1 text-xs rounded-md min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-expanded="isOpen"
      :aria-controls="listId"
      :disabled="!entries.length"
      @click="isOpen = !isOpen"
    >
      <span class="i-lucide-pencil size-3" aria-hidden="true" />
      {{ t('MESSAGE_ACTIONS.EDITED') }}
      <span
        v-if="entries.length"
        class="size-3"
        :class="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        aria-hidden="true"
      />
      <span class="sr-only">{{
        t('MESSAGE_ACTIONS.EDIT_HISTORY_TOGGLE')
      }}</span>
    </button>
    <ol
      v-show="isOpen"
      :id="listId"
      data-edit-history
      :aria-label="t('MESSAGE_ACTIONS.EDIT_HISTORY')"
      class="flex flex-col gap-2 p-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
    >
      <li v-for="entry in entries" :key="entry.key" class="flex flex-col">
        <span class="text-xs text-n-slate-11">{{ entry.author }}</span>
        <span class="whitespace-pre-wrap break-words">{{ entry.content }}</span>
      </li>
    </ol>
  </div>
</template>
