<script setup>
// Opções: `{ type: 'options', options?, sections?, header?, footer?, button? }`, com o corpo em `content`.
// Até três opções soltas e sem descrição viram botões; com seções, mais de três ou alguma descrição, lista
// (a mesma regra do envio, `app/services/rich_messages/types/options.rb`). Mostra qual o cliente tocou.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../../../provider.js';
import Frame from '../Frame.vue';
import ActionRow from '../ActionRow.vue';
import OptionsList from '../OptionsList.vue';
import { selectedOptionFor } from '../optionsAnswer.js';
import OpcoesDoWhatsapp from '../../../../conversa-canal/OpcoesDoWhatsapp.vue';
import { usePele } from '../../../../conversa-canal/pele';

const BUTTONS_MAX = 3;

const { id, contentAttributes } = useMessageContext();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');
// #1702: na conversa com a cara do WhatsApp, os botões ficam soltos embaixo do balão.
const pele = usePele();

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

// As seções como saíram para a Meta: a seção única sem título sai com o texto do botão da lista (o envio faz o
// mesmo, porque a Meta pede título em toda seção). A bolha é espelho do que o cliente recebeu.
const sentSections = computed(() => {
  const [only, ...others] = sections.value;
  if (others.length || only.title) return sections.value;
  return [{ ...only, title: textOf(richMessage.value.button) }];
});

const answer = computed(() =>
  selectedOptionFor(id.value, currentChat.value?.messages)
);
const chosenId = computed(() => answer.value?.id ?? '');
// O título como foi oferecido; se a opção não está na mensagem, o que o cliente tocou; sem nenhum dos dois, vazio.
const chosenTitle = computed(
  () =>
    allOptions.value.find(option => option.id === chosenId.value)?.title ||
    textOf(answer.value?.title)
);

// Só afirma o que achou: sem resposta carregada (o cliente pode ter respondido fora do que está na tela) ou sem
// título para dizer, não há linha.
const chosenLine = computed(() =>
  chosenTitle.value
    ? t('RICH_MESSAGE.OPTIONS.CHOSEN', { title: chosenTitle.value })
    : ''
);
</script>

<template>
  <OpcoesDoWhatsapp
    v-if="pele"
    :header="textOf(richMessage.header)"
    :footer="textOf(richMessage.footer)"
    :is-list="isList"
    :list-button="textOf(richMessage.button)"
    :options="allOptions"
    :sections="sentSections"
    :chosen-id="chosenId"
    :chosen-line="chosenLine"
  />
  <Frame
    v-else
    bubble-name="rich-options"
    :header="textOf(richMessage.header)"
    :footer="textOf(richMessage.footer)"
  >
    <div class="flex flex-col gap-1.5">
      <span class="sr-only">{{ t('RICH_MESSAGE.OPTIONS.MIRROR') }}</span>
      <template v-if="isList">
        <ActionRow icon="i-lucide-list" :label="textOf(richMessage.button)" />
        <OptionsList :sections="sentSections" :chosen-id="chosenId" />
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
        v-if="chosenLine"
        class="text-xs font-medium text-n-slate-11 break-words"
      >
        {{ chosenLine }}
      </div>
    </div>
  </Frame>
</template>
