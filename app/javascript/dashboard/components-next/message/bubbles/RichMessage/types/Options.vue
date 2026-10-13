<script setup>
// Opções: `{ type: 'options', options?, sections?, header?, footer?, button? }`, com o corpo em `content`.
// Até três opções soltas e sem descrição viram botões; com seções, mais de três ou alguma descrição, lista
// (a mesma regra do envio, `app/services/rich_messages/types/options.rb`). Mostra qual o cliente tocou.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../../../provider.js';
import { MESSAGE_STATUS } from '../../../constants';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';
import OptionsList from '../OptionsList.vue';
import { selectedOptionFor } from '../optionsAnswer.js';

const BUTTONS_MAX = 3;

const { id, status, contentAttributes } = useMessageContext();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

// Tudo vem de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');
const listOf = value => (Array.isArray(value) ? value : []);
const optionsOf = value =>
  listOf(value)
    .map(option => ({
      id: textOf(option?.id),
      title: textOf(option?.title),
      description: textOf(option?.description),
    }))
    .filter(option => option.title);

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});
const hasSections = computed(() => Array.isArray(richMessage.value.sections));
const sections = computed(() => {
  if (!hasSections.value) {
    return [{ title: '', options: optionsOf(richMessage.value.options) }];
  }
  return richMessage.value.sections.map(section => ({
    title: textOf(section?.title),
    options: optionsOf(section?.options),
  }));
});
const allOptions = computed(() =>
  sections.value.flatMap(section => section.options)
);
const isList = computed(
  () =>
    hasSections.value ||
    allOptions.value.length > BUTTONS_MAX ||
    allOptions.value.some(option => option.description)
);

const answer = computed(() =>
  selectedOptionFor(id.value, currentChat.value?.messages)
);
const chosenId = computed(() => answer.value?.id ?? '');
// O título como foi oferecido; se a opção não está mais na mensagem, o que o cliente tocou.
const chosenTitle = computed(
  () =>
    allOptions.value.find(option => option.id === chosenId.value)?.title ||
    textOf(answer.value?.title)
);

const statusLine = computed(() => {
  if (status.value === MESSAGE_STATUS.FAILED) return '';
  if (answer.value) {
    return t('RICH_MESSAGE.OPTIONS.CHOSEN', { title: chosenTitle.value });
  }
  return t('RICH_MESSAGE.OPTIONS.WAITING');
});
</script>

<template>
  <Frame
    bubble-name="rich-options"
    :header="textOf(richMessage.header)"
    :footer="textOf(richMessage.footer)"
  >
    <div class="flex flex-col gap-1.5">
      <template v-if="isList">
        <ActionRow
          icon="i-lucide-list"
          :label="
            textOf(richMessage.button) ||
            t('RICH_MESSAGE.OPTIONS.LIST_BUTTON_DEFAULT')
          "
        />
        <OptionsList :sections="sections" :chosen-id="chosenId" />
      </template>
      <template v-else>
        <ActionRow
          v-for="(option, index) in allOptions"
          :key="index"
          data-option-button
          :icon="chosenId && option.id === chosenId ? 'i-lucide-check' : ''"
          :label="option.title"
        />
      </template>
      <div
        v-if="statusLine"
        class="text-xs font-medium text-n-slate-11 break-words"
      >
        {{ statusLine }}
      </div>
    </div>
  </Frame>
</template>
