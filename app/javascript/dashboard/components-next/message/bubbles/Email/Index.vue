<script setup>
import { computed, useTemplateRef, ref, onMounted } from 'vue';
import { Letter } from 'vue-letter';
import { sanitizeTextForRender } from '@chatwoot/utils';
import { allowedCssProperties } from 'lettersanitizer';

import Icon from 'next/icon/Icon.vue';
import { EmailQuoteExtractor } from 'dashboard/helper/emailQuoteExtractor.js';
import FormattedContent from 'next/message/bubbles/Text/FormattedContent.vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import EmailMeta from './EmailMeta.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';

import { useMessageContext } from '../../provider.js';
import { MESSAGE_TYPES } from 'next/message/constants.js';
import { useTranslations } from 'dashboard/composables/useTranslations';
import CartaoDoEmail from 'dashboard/components-next/conversa-canal/email/CartaoDoEmail.vue';
import CorpoIsoladoDoEmail from 'dashboard/components-next/conversa-canal/email/CorpoIsoladoDoEmail.vue';
import {
  citacaoDoDocumento,
  imagemSemRastreio,
} from 'dashboard/components-next/conversa-canal/email/documentoDoEmail';
import { useEmailDaConversa } from 'dashboard/components-next/conversa-canal/email/useConversaDeEmail';
import { htmlComCssSeguro } from 'dashboard/components-next/conversa-canal/email/estiloSeguroDoEmail';

const { content, contentAttributes, attachments, messageType } =
  useMessageContext();
// #1786: com a conversa de e-mail nova ligada, o cartão com a cara do Gmail.
const emailNovo = useEmailDaConversa().ligado;

const isExpandable = ref(false);
const isExpanded = ref(false);
const showQuotedMessage = ref(false);
const renderOriginal = ref(false);
const contentContainer = useTemplateRef('contentContainer');

onMounted(() => {
  isExpandable.value = contentContainer.value?.scrollHeight > 400;
});

const isOutgoing = computed(() => messageType.value === MESSAGE_TYPES.OUTGOING);
const isIncoming = computed(() => !isOutgoing.value);

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const originalEmailText = computed(() => {
  const text =
    contentAttributes?.value?.email?.textContent?.full ?? content.value;
  return sanitizeTextForRender(text);
});

const originalEmailHtml = computed(
  () =>
    contentAttributes?.value?.email?.htmlContent?.full ||
    originalEmailText.value
);

const hasEmailContent = computed(() => {
  return (
    contentAttributes?.value?.email?.textContent?.full ||
    contentAttributes?.value?.email?.htmlContent?.full
  );
});

const messageContent = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original content
  return content.value;
});

const textToShow = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original text
  return originalEmailText.value;
});

const fullHTML = computed(() => {
  // If translations exist and we're showing translations (not original)
  if (hasTranslations.value && !renderOriginal.value) {
    return translationContent.value;
  }
  // Otherwise show original HTML
  return originalEmailHtml.value;
});

// #1884: o HTML recebido do remetente vai inteiro para a moldura isolada, com o mesmo
// extrator de citação de sempre (só o do Chatwoot), aplicado no documento inteiro.
const senderHtml = computed(
  () =>
    messageType.value === MESSAGE_TYPES.INCOMING &&
    Boolean(contentAttributes?.value?.email?.htmlContent?.full)
);
const unquotedDocument = computed(() =>
  senderHtml.value
    ? citacaoDoDocumento(fullHTML.value, { leitores: false })
    : null
);

const unquotedHTML = computed(() =>
  EmailQuoteExtractor.extractQuotes(fullHTML.value)
);
// O CSS do remetente não pode escapar do <style> ao passar pelo vue-letter (estiloSeguroDoEmail).
// Imagem e url() do CSS (inclusive image-set) só com endereço completo: relativo
// pediria ao painel.
const recursoSeguro = imagemSemRastreio(endereco => endereco);
const fullHTMLSeguro = computed(() =>
  htmlComCssSeguro(fullHTML.value, { conferirUrls: true })
);
const unquotedHTMLSeguro = computed(() =>
  htmlComCssSeguro(unquotedHTML.value, { conferirUrls: true })
);

const hasQuotedMessage = computed(() =>
  unquotedDocument.value
    ? unquotedDocument.value.achou
    : EmailQuoteExtractor.hasQuotes(fullHTML.value)
);

const measureIsolatedBody = height => {
  isExpandable.value = height > 400;
};

// Ensure unique keys for <Letter> when toggling between original and translated views.
// This forces Vue to re-render the component and update content correctly.
const translationKeySuffix = computed(() => {
  if (renderOriginal.value) return 'original';
  if (hasTranslations.value) return 'translated';
  return 'original';
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <CartaoDoEmail v-if="emailNovo" />
  <BaseBubble
    v-else
    class="w-full"
    :class="{
      'bg-n-slate-4': isIncoming,
      'bg-n-solid-blue': isOutgoing,
    }"
    data-bubble-name="email"
  >
    <EmailMeta
      class="p-3"
      :class="{
        'border-b border-n-strong': isIncoming,
        'border-b border-n-slate-8/20': isOutgoing,
      }"
    />
    <section ref="contentContainer" class="p-3">
      <div
        :class="{
          'max-h-[400px] overflow-hidden relative': !isExpanded && isExpandable,
          'overflow-y-scroll relative': isExpanded,
        }"
      >
        <div
          v-if="isExpandable && !isExpanded"
          class="absolute left-0 right-0 bottom-0 h-40 px-8 flex items-end"
          :class="{
            'bg-gradient-to-t from-n-slate-4 via-n-slate-4 via-20% to-transparent':
              isIncoming,
            'bg-gradient-to-t from-n-solid-blue via-n-solid-blue via-20% to-transparent':
              isOutgoing,
          }"
        >
          <button
            class="text-n-slate-12 py-2 px-8 mx-auto text-center flex items-center gap-2"
            @click="isExpanded = true"
          >
            <Icon icon="i-lucide-maximize-2" />
            {{ $t('EMAIL_HEADER.EXPAND') }}
          </button>
        </div>
        <FormattedContent
          v-if="isOutgoing && content && !hasEmailContent"
          class="text-n-slate-12"
          :content="messageContent"
        />
        <template v-else>
          <CorpoIsoladoDoEmail
            v-if="senderHtml"
            :html="showQuotedMessage ? fullHTML : unquotedDocument.html"
            :titulo="$t('CONVERSA_CANAL.EMAIL.CORPO_DO_EMAIL')"
            @altura="measureIsolatedBody"
          />
          <Letter
            v-else-if="showQuotedMessage"
            :key="`letter-quoted-${translationKeySuffix}`"
            class-name="prose prose-bubble !max-w-none letter-render"
            :allowed-css-properties="[
              ...allowedCssProperties,
              'transform',
              'transform-origin',
            ]"
            :html="fullHTMLSeguro"
            :rewrite-external-resources="recursoSeguro"
            :text="textToShow"
          />
          <Letter
            v-else
            :key="`letter-unquoted-${translationKeySuffix}`"
            class-name="prose prose-bubble !max-w-none letter-render"
            :html="unquotedHTMLSeguro"
            :rewrite-external-resources="recursoSeguro"
            :allowed-css-properties="[
              ...allowedCssProperties,
              'transform',
              'transform-origin',
            ]"
            :text="textToShow"
          />
        </template>
        <button
          v-if="hasQuotedMessage"
          class="text-n-slate-11 px-1 leading-none text-sm bg-n-alpha-black2 text-center flex items-center gap-1 mt-2"
          @click="showQuotedMessage = !showQuotedMessage"
        >
          <template v-if="showQuotedMessage">
            {{ $t('CHAT_LIST.HIDE_QUOTED_TEXT') }}
          </template>
          <template v-else>
            {{ $t('CHAT_LIST.SHOW_QUOTED_TEXT') }}
          </template>
          <Icon
            :icon="
              showQuotedMessage
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
          />
        </button>
      </div>
    </section>
    <TranslationToggle
      v-if="hasTranslations"
      class="py-2 px-3"
      :showing-original="renderOriginal"
      @toggle="handleSeeOriginal"
    />
    <section
      v-if="Array.isArray(attachments) && attachments.length"
      class="px-4 pb-4 space-y-2"
    >
      <AttachmentChips :attachments="attachments" class="gap-1" />
    </section>
  </BaseBubble>
</template>

<style lang="scss">
// Tailwind resets break the rendering of google drive link in Gmail messages
// This fixes it using https://developer.mozilla.org/en-US/docs/Web/CSS/Attribute_selectors

.letter-render [class*='gmail_drive_chip'] {
  box-sizing: initial;
  @apply bg-n-slate-4 border-n-slate-6 rounded-md !important;

  a {
    @apply text-n-slate-12 !important;

    img {
      display: inline-block;
    }
  }
}

// Email clients (Gmail, Outlook) hardcode dir="ltr" on wrapper elements.
// In RTL apps this forces email content LTR regardless of actual text.
[dir='rtl'] .letter-render [dir='ltr'] {
  direction: inherit;
}
</style>
