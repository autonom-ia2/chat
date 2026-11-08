<script setup>
import { computed, useAttrs } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION, SENDER_TYPES } from '../constants';
import { usePeleDoBalao } from '../../conversa-canal/usePeleDoBalao';
import BicoDoBalao from '../../conversa-canal/BicoDoBalao.vue';
import BotoesDoModelo from '../../conversa-canal/BotoesDoModelo.vue';
import OrigemDaMensagem from '../../conversa-canal/OrigemDaMensagem.vue';
import BotaoDoMenu from '../../conversa-canal/BotaoDoMenu.vue';
import CitacaoDoWhatsapp from '../../conversa-canal/CitacaoDoWhatsapp.vue';
import SeloDeReacoes from '../../conversa-canal/SeloDeReacoes.vue';
import SeloVisualizacaoUnica from '../../conversa-canal/SeloVisualizacaoUnica.vue';
import { temVisualizacaoUnica } from '../../conversa-canal/visualizacaoUnica';
import { useReacoesDoBalao } from '../../conversa-canal/useReacoesDoBalao';
import RotuloEncaminhada from '../../conversa-canal/RotuloEncaminhada.vue';
import SeloApagadaPeloCliente from '../../conversa-canal/SeloApagadaPeloCliente.vue';
import {
  apagadaPeloCliente,
  encaminhamento,
} from '../../conversa-canal/marcasDaMensagem';
import { previaDoAnexoCitado } from '../../conversa-canal/citacaoDoAnexo';
import { citacaoSolta } from '../../conversa-canal/citacaoSolta';
import { previaDaCitada } from '../../conversa-canal/useFormatoDoWhatsapp';
import { textoDaMensagem } from '../../conversa-canal/ecoDoCelular';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  id,
  sender,
  senderType,
  attachments: anexosDoBalao,
  contentAttributes: atributosDoBalao,
} = useMessageContext();
const { t } = useI18n();
// #1702: com a pele do canal (WhatsApp), cor, cantos, bico, hora e remetente do app.
const peleDoBalao = usePeleDoBalao(useAttrs()['data-bubble-name']);
// #1702: reação do cliente = selo com o emoji embaixo do balão (só com a pele).
const reacoesDoBalao = useReacoesDoBalao(peleDoBalao.ativa);
// #1702: visualização única = rótulo em cima da mídia, que continua aparecendo.
const visualizacaoUnica = computed(
  () => peleDoBalao.ativa.value && temVisualizacaoUnica(anexosDoBalao?.value)
);

// #1702: "Encaminhada" e "Apagada pelo cliente" no topo do balão (só com a pele).
const encaminhada = computed(() =>
  peleDoBalao.ativa.value ? encaminhamento(atributosDoBalao?.value) : null
);
const apagada = computed(
  () => peleDoBalao.ativa.value && apagadaPeloCliente(atributosDoBalao?.value)
);

// #1709: citação de mensagem que não está nesta conversa (quoted_message), só com a pele.
const citacaoSoltaDoBalao = computed(() =>
  peleDoBalao.ativa.value && !inReplyTo?.value
    ? citacaoSolta(atributosDoBalao?.value)
    : null
);

const isCaptainMessage = computed(
  () =>
    (sender.value?.type ?? senderType.value) === SENDER_TYPES.CAPTAIN_ASSISTANT
);

const metaColorClass = computed(
  () =>
    peleDoBalao.classesDaHora.value ||
    (variant.value === MESSAGE_VARIANTS.PRIVATE
      ? 'text-n-amber-12/50'
      : 'text-n-slate-11')
);

const emailMetaClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : ''
);

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-solid-blue text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  if (peleDoBalao.classesDoBalao.value)
    return [peleDoBalao.classesDoBalao.value];

  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    (peleDoBalao.ativa.value || !shouldGroupWithNext.value) &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { attachments, contentAttributes: atributosDaCitada } = inReplyTo.value;
  // #1941: citação de mensagem mandada pelo celular, sem o prefixo do conector.
  const content = textoDaMensagem(inReplyTo.value.content, atributosDaCitada);

  // #1740: com a pele, a citação lê o texto como o balão dela (formato do WhatsApp).
  if (content && peleDoBalao.ativa.value)
    return previaDaCitada({ ...inReplyTo.value, content });
  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    // #1702: com a pele, os rótulos da citação do app ("Foto", "Figurinha", o nome do
    // documento); o ícone e a miniatura saem na própria CitacaoDoWhatsapp.
    if (peleDoBalao.ativa.value) {
      return previaDoAnexoCitado(inReplyTo.value, t);
    }
    const fileType = attachments[0].fileType ?? attachments[0].file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
        'mb-[18px]': reacoesDoBalao.temReacoes.value,
      },
    ]"
  >
    <!-- #1702: aviso de atividade não tem menu (é uma pílula do sistema). -->
    <BotaoDoMenu
      v-if="peleDoBalao.ativa.value && variant !== MESSAGE_VARIANTS.ACTIVITY"
    />
    <BicoDoBalao
      v-if="peleDoBalao.bico.value"
      :lado="orientation"
      :class="peleDoBalao.bico.value"
    />
    <div
      v-if="peleDoBalao.remetente.value"
      :class="peleDoBalao.classesDoRemetente"
    >
      {{ peleDoBalao.remetente.value }}
    </div>
    <SeloApagadaPeloCliente v-if="apagada" />
    <RotuloEncaminhada v-if="encaminhada" :tipo="encaminhada" />
    <!-- #1702: anúncio ou produto do catálogo que o cliente citou. -->
    <OrigemDaMensagem v-if="peleDoBalao.ativa.value" />
    <BotoesDoModelo v-if="peleDoBalao.ativa.value" parte="topo" />
    <CitacaoDoWhatsapp
      v-if="inReplyTo && peleDoBalao.ativa.value"
      :mensagem="inReplyTo"
      :previa="replyToPreview"
      @ir="scrollToMessage"
    />
    <div
      v-else-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <CitacaoDoWhatsapp
      v-if="citacaoSoltaDoBalao"
      :solta="citacaoSoltaDoBalao"
      :nome-do-cliente="sender?.name || ''"
    />
    <SeloVisualizacaoUnica v-if="visualizacaoUnica" />
    <slot />
    <BotoesDoModelo v-if="peleDoBalao.ativa.value" parte="rodape" />
    <template v-if="shouldShowMeta">
      <CaptainGenerationDetails
        v-if="isCaptainMessage"
        :message-id="id"
        class="mt-2"
      >
        <template #meta>
          <MessageMeta :class="[emailMetaClass, metaColorClass]" />
        </template>
      </CaptainGenerationDetails>
      <MessageMeta
        v-else
        :class="[
          peleDoBalao.ativa.value ? '' : flexOrientationClass,
          emailMetaClass,
          metaColorClass,
          peleDoBalao.ativa.value ? 'mt-0.5' : 'mt-2',
        ]"
      />
    </template>
    <BotoesDoModelo v-if="peleDoBalao.ativa.value" parte="botoes" />
    <SeloDeReacoes
      v-if="reacoesDoBalao.temReacoes.value"
      :reacoes="reacoesDoBalao.reacoes.value"
      :lado="reacoesDoBalao.lado.value"
      :nome-do-cliente="reacoesDoBalao.nomeDoCliente.value"
    />
  </div>
</template>
