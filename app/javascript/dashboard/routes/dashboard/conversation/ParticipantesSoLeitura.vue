<script setup>
import { computed, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// Quem só lê (#1800) vê quem participa, sem adicionar nem tirar ninguém.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const store = useStore();
const participants = computed(() =>
  store.getters['conversationWatchers/getByConversationId'](
    props.conversationId
  )
);

watch(
  () => props.conversationId,
  conversationId =>
    store.dispatch('conversationWatchers/show', { conversationId }),
  { immediate: true }
);
</script>

<template>
  <ul
    v-if="participants?.length"
    class="flex flex-col gap-2 m-0 list-none"
    data-participantes-so-leitura
  >
    <li
      v-for="participant in participants"
      :key="participant.id"
      class="flex items-center gap-2 text-sm text-n-slate-12"
    >
      <Avatar
        :name="participant.name"
        :src="participant.thumbnail || ''"
        :size="20"
        rounded-full
      />
      <span class="truncate">{{ participant.name }}</span>
    </li>
  </ul>
  <span v-else class="text-sm text-n-slate-11" data-participantes-so-leitura>
    {{ $t('CONVERSATION.SO_LEITURA.SEM_PARTICIPANTES') }}
  </span>
</template>
