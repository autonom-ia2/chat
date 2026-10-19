<script setup>
// As reações coladas na mensagem (chat#1709, fase 3): a do cliente e a da empresa (atendentes, IA e celular da empresa
// são um autor só, como no WhatsApp), agrupadas por emoji. Só leitura; reagir é pelo menu da mensagem. Cada chip diz
// em texto quem reagiu (leitor de tela) e a do cliente tem cor própria, para o 👍 de confirmação não passar batido.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { groupReactions } from './messageActions.js';

const props = defineProps({
  reactions: { type: Array, default: () => [] },
  currentUserId: { type: Number, default: null },
});

const { t } = useI18n();
const groups = computed(() =>
  groupReactions(props.reactions, props.currentUserId)
);

const authorOf = group => {
  if (group.fromContact && group.fromBusiness) {
    return t('MESSAGE_ACTIONS.REACTION_BY_BOTH');
  }
  if (group.fromContact) return t('MESSAGE_ACTIONS.REACTION_BY_CONTACT');
  return group.mine
    ? t('MESSAGE_ACTIONS.REACTION_BY_YOU')
    : t('MESSAGE_ACTIONS.REACTION_BY_BUSINESS');
};
</script>

<template>
  <ul
    class="flex flex-wrap gap-1"
    data-message-reactions
    :aria-label="t('MESSAGE_ACTIONS.REACTIONS_LABEL')"
  >
    <li
      v-for="group in groups"
      :key="group.emoji"
      :title="`${group.emoji} ${authorOf(group)}`"
      :data-reaction-from-contact="group.fromContact || null"
      class="flex items-center gap-1 px-2 py-0.5 text-sm border rounded-full"
      :class="[
        group.fromContact
          ? 'bg-n-teal-3 border-n-teal-9'
          : 'bg-n-solid-2 border-n-weak',
        { 'ring-1 ring-n-brand': group.mine },
      ]"
    >
      <span aria-hidden="true">{{ group.emoji }}</span>
      <span
        v-if="group.count > 1"
        aria-hidden="true"
        class="text-xs text-n-slate-11"
      >
        {{ group.count }}
      </span>
      <span class="sr-only">{{ `${group.emoji} ${authorOf(group)}` }}</span>
    </li>
  </ul>
</template>
