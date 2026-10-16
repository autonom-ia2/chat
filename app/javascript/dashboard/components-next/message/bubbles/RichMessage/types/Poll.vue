<script setup>
// Enquete (chat#1709, fase 3): `{ type: 'poll', options: [{ id, title }], multiple? }`, com a pergunta em `content`.
// Mostra as opções como o cliente recebeu (só leitura) e o voto mais recente ("Votou: X"); o voto trocado atualiza
// sozinho e o retirado volta a "sem voto" (pollAnswer.js).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import { pollVoteFor } from '../pollAnswer.js';

const { id, contentAttributes } = useMessageContext();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

// Tudo vem de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});
const options = computed(() =>
  (Array.isArray(richMessage.value.options) ? richMessage.value.options : [])
    .map(option => ({ id: textOf(option?.id), title: textOf(option?.title) }))
    .filter(option => option.title)
);
const isMultiple = computed(() => richMessage.value.multiple === true);

const vote = computed(() => pollVoteFor(id.value, currentChat.value?.messages));
const votedIds = computed(() => (vote.value ?? []).map(option => option.id));
const isVoted = option => votedIds.value.includes(option.id);

// O título como foi oferecido; se a opção não está na enquete, o que o voto trouxe.
const votedTitles = computed(() =>
  (vote.value ?? [])
    .map(
      option =>
        options.value.find(offered => offered.id === option.id)?.title ||
        textOf(option.title)
    )
    .filter(Boolean)
);

const voteLine = computed(() => {
  if (vote.value === null) return '';
  if (!votedTitles.value.length) return t('RICH_MESSAGE.POLL.NO_VOTE');
  return t('RICH_MESSAGE.POLL.VOTED', { titles: votedTitles.value.join(', ') });
});
</script>

<template>
  <Frame bubble-name="rich-poll">
    <div class="flex flex-col gap-1.5">
      <span class="sr-only">{{ t('RICH_MESSAGE.POLL.MIRROR') }}</span>
      <div class="flex items-center gap-1.5 text-xs text-n-slate-11">
        <Icon icon="i-lucide-chart-bar" class="size-3.5 flex-shrink-0" />
        <span>
          {{
            isMultiple
              ? t('RICH_MESSAGE.POLL.MULTIPLE')
              : t('RICH_MESSAGE.POLL.SINGLE')
          }}
        </span>
      </div>
      <ul
        class="rounded-lg border border-n-container bg-n-solid-3 overflow-hidden py-1"
      >
        <li
          v-for="(option, index) in options"
          :key="index"
          data-poll-option
          class="flex items-center gap-2 px-3 py-2"
          :class="{ 'bg-n-alpha-2': isVoted(option) }"
        >
          <span
            class="flex-1 min-w-0 text-sm text-n-slate-12 break-words"
            :class="{ 'font-medium': isVoted(option) }"
          >
            {{ option.title }}
          </span>
          <Icon
            v-if="isVoted(option)"
            icon="i-lucide-check"
            class="size-4 flex-shrink-0 text-n-teal-11"
          />
        </li>
      </ul>
      <div
        v-if="voteLine"
        data-poll-vote
        class="text-xs font-medium text-n-slate-11 break-words"
      >
        {{ voteLine }}
      </div>
    </div>
  </Frame>
</template>
