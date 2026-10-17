<script setup>
// #1702: a mensagem respondida, dentro do balão, como no WhatsApp: faixa colorida à
// esquerda, o nome de quem escreveu na mesma cor, o texto em até três linhas e a
// miniatura da foto à direita. Verde para a empresa, roxo para o cliente. A prévia
// pode trazer link: ele vira texto (a citação inteira é um botão, e link dentro de
// botão ganharia foco à toa); o toque na citação leva à mensagem.
// #1709: a citação "solta" (citacaoSolta.js) é de mensagem que não está nesta
// conversa: o mesmo desenho, com o ícone do anexo, e sem o toque (não há aonde ir).
// Trecho não conferido (só o aparelho do cliente o mandou): sem nome, faixa cinza e o
// aviso embaixo, porque o autor que veio junto pode ter sido forjado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_TYPES } from '../message/constants';

const props = defineProps({
  mensagem: { type: Object, default: null },
  previa: { type: String, default: '' },
  // Resultado de citacaoSolta(); no lugar de `mensagem` e `previa`.
  solta: { type: Object, default: null },
  // Sem ir a lugar nenhum (a citação em cima da caixa de resposta): sem papel de botão.
  inerte: { type: Boolean, default: false },
  // Nome do cliente da conversa, para a citação solta de mensagem dele.
  nomeDoCliente: { type: String, default: '' },
});
const emit = defineEmits(['ir']);
const { t } = useI18n();

const ICONES = {
  image: 'i-ph-camera-fill',
  video: 'i-ph-video-camera-fill',
  audio: 'i-ph-microphone-fill',
  file: 'i-ph-file-fill',
  location: 'i-ph-map-pin-fill',
  contact: 'i-ph-user-fill',
  midia: 'i-ph-paperclip',
};

// Chaves escritas por extenso: a trava de i18n confere cada uma.
const NOMES_DO_ANEXO = {
  image: 'CONVERSA_CANAL.CITACAO.FOTO',
  video: 'CONVERSA_CANAL.CITACAO.VIDEO',
  audio: 'CONVERSA_CANAL.CITACAO.AUDIO',
  file: 'CONVERSA_CANAL.CITACAO.DOCUMENTO',
  location: 'CONVERSA_CANAL.CITACAO.LOCALIZACAO',
  contact: 'CONVERSA_CANAL.CITACAO.CONTATO',
  midia: 'CONVERSA_CANAL.CITACAO.MIDIA',
};

const clicavel = computed(() => !props.solta && !props.inerte);
const naoConferida = computed(() => Boolean(props.solta?.naoConferida));
const doCliente = computed(() =>
  props.solta
    ? !props.solta.daEmpresa
    : props.mensagem?.messageType === MESSAGE_TYPES.INCOMING
);

const FAIXA = {
  neutra: 'border-s-[#8696A0]',
  cliente: 'border-s-[#5E44D8] dark:border-s-[#B3A1FF]',
  empresa: 'border-s-[#1A6B42] dark:border-s-[#6FD07E]',
};
const faixa = computed(() => {
  if (naoConferida.value) return FAIXA.neutra;
  return doCliente.value ? FAIXA.cliente : FAIXA.empresa;
});

// Sem nome (sistema, robô sem cadastro), a citação fica só com o texto. Na solta, a
// empresa é "Você", como o app mostra a mensagem do próprio número. A não conferida
// fica sem nome.
const nome = computed(() => {
  if (!props.solta) return props.mensagem?.sender?.name || '';
  if (naoConferida.value) return '';
  return props.solta.daEmpresa
    ? t('CONVERSA_CANAL.CITACAO.VOCE')
    : props.nomeDoCliente;
});
const icone = computed(() => ICONES[props.solta?.anexo] || '');

const previaDaSolta = computed(() => {
  const { texto, anexo } = props.solta;
  if (texto) return new MessageFormatter(texto).formattedMessage;
  if (anexo) return t(NOMES_DO_ANEXO[anexo]);
  return t('CONVERSA_CANAL.CITACAO.SEM_TEXTO');
});

// Tira os links da prévia e mantém o texto e a formatação (negrito, itálico).
const previaSemLinks = computed(() => {
  const html = props.solta ? previaDaSolta.value : props.previa;
  if (!html) return '';
  const documento = new DOMParser().parseFromString(html, 'text/html');
  documento.body
    .querySelectorAll('a')
    .forEach(link => link.replaceWith(...link.childNodes));
  return documento.body.innerHTML;
});
const foto = computed(() => {
  const anexo = props.mensagem?.attachments?.[0];
  const tipo = anexo?.fileType ?? anexo?.file_type;
  if (tipo !== 'image') return '';
  return anexo.thumbUrl ?? anexo.thumb_url ?? anexo.dataUrl ?? anexo.data_url;
});

const ir = () => {
  if (clicavel.value) emit('ir');
};
</script>

<template>
  <div
    :role="clicavel ? 'button' : undefined"
    :tabindex="clicavel ? 0 : undefined"
    class="flex w-full min-w-0 mb-1 overflow-hidden text-start rounded-[7.5px] border-s-4 bg-[#000]/[0.05] dark:bg-[#000]/20"
    :class="[faixa, clicavel ? 'cursor-pointer' : '']"
    :data-citacao-solta="solta ? '' : undefined"
    @click="ir"
    @keydown.enter.prevent="ir"
    @keydown.space.prevent="ir"
  >
    <span class="flex-1 min-w-0 px-2 py-1.5">
      <span
        v-if="nome"
        class="block text-[12.8px] leading-[20px] font-medium truncate"
        :class="
          doCliente
            ? 'text-[#5E44D8] dark:text-[#B3A1FF]'
            : 'text-[#1A6B42] dark:text-[#6FD07E]'
        "
      >
        {{ nome }}
      </span>
      <span
        class="flex items-start gap-1 text-[13px] leading-[18px] text-[#666666] dark:text-[#B5C2BC]"
      >
        <span
          v-if="icone"
          class="size-4 mt-px shrink-0"
          :class="icone"
          aria-hidden="true"
        />
        <span
          v-dompurify-html="previaSemLinks"
          class="block min-w-0 line-clamp-3 [&_p]:m-0"
        />
      </span>
      <span
        v-if="solta?.outraConversa"
        class="block text-[12px] leading-[16px] italic text-[#666666] dark:text-[#B5C2BC]"
        data-citacao-de-outra-conversa
      >
        {{ t('CONVERSA_CANAL.CITACAO.OUTRA_CONVERSA') }}
      </span>
      <span
        v-if="naoConferida"
        class="block text-[12px] leading-[16px] italic text-[#666666] dark:text-[#B5C2BC]"
        data-citacao-nao-conferida
      >
        {{ t('CONVERSA_CANAL.CITACAO.NAO_CONFERIDA') }}
      </span>
    </span>
    <img
      v-if="foto"
      :src="foto"
      alt=""
      class="size-[60px] object-cover shrink-0"
    />
  </div>
</template>
