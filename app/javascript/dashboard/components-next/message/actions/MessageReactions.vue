<script setup>
// As reações coladas na mensagem (chat#1709, fase 3): do cliente, do celular da empresa e dos atendentes, agrupadas por
// emoji. Só leitura; reagir é pelo menu da mensagem.
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
      class="flex items-center gap-1 px-2 py-0.5 text-sm rounded-full border border-n-weak bg-n-solid-2"
      :class="{ 'border-n-brand': group.mine }"
    >
      <span>{{ group.emoji }}</span>
      <span v-if="group.count > 1" class="text-xs text-n-slate-11">
        {{ group.count }}
      </span>
    </li>
  </ul>
</template>
