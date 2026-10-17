<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import PreviaDeLink from 'dashboard/components-next/conversa-canal/PreviaDeLink.vue';
import { usePreviaDeLink } from 'dashboard/components-next/conversa-canal/usePreviaDeLink';
import DocumentoDoWhatsapp from 'dashboard/components-next/conversa-canal/midia/DocumentoDoWhatsapp.vue';
import MidiaComLegenda from 'dashboard/components-next/conversa-canal/midia/MidiaComLegenda.vue';
import { usePele } from 'dashboard/components-next/conversa-canal/pele';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { ATTACHMENT_TYPES, MESSAGE_TYPES } from '../../constants';
import { MESSAGE_STATUS } from 'shared/constants/messages';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType, status } =
  useMessageContext();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const previaDeLink = usePreviaDeLink();

// #1702: com a pele, documento, foto e vídeo com legenda ficam como no app (cartão ou
// mídia no tamanho do app, em cima da legenda); os outros anexos seguem nos chips.
const pele = usePele();
const ehDocumento = anexo => anexo.fileType === ATTACHMENT_TYPES.FILE;
const MIDIAS = [ATTACHMENT_TYPES.IMAGE, ATTACHMENT_TYPES.VIDEO];
const ehMidia = anexo => MIDIAS.includes(anexo.fileType);
const doTipo = filtro =>
  computed(() => (pele.value ? (attachments.value || []).filter(filtro) : []));
const documentos = doTipo(ehDocumento);
const midias = doTipo(ehMidia);
const outrosAnexos = computed(() =>
  pele.value
    ? (attachments.value || []).filter(
        anexo => !ehDocumento(anexo) && !ehMidia(anexo)
      )
    : attachments.value
);

const renderOriginal = ref(false);

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const contactInfoRequestState = computed(() => {
  if (status.value === MESSAGE_STATUS.FAILED) return null;

  return contentAttributes.value?.whatsappContactInfo?.state;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <MidiaComLegenda v-for="midia in midias" :key="midia.id" :anexo="midia" />
      <DocumentoDoWhatsapp
        v-for="documento in documentos"
        :key="documento.id"
        :anexo="documento"
      />
      <PreviaDeLink v-if="previaDeLink" :previa="previaDeLink" />
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <span
        v-if="contactInfoRequestState === 'pending'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.PENDING') }}
      </span>
      <span
        v-else-if="contactInfoRequestState === 'shared'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.SHARED') }}
      </span>
      <span
        v-else-if="contactInfoRequestState === 'identity_conflict'"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('CONVERSATION.REQUEST_CONTACT_INFO.STATES.IDENTITY_CONFLICT') }}
      </span>
      <TranslationToggle
        v-if="hasTranslations"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="outrosAnexos" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
