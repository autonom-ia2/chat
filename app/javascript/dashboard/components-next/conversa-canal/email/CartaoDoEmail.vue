<script setup>
// Um e-mail da conversa com a cara do Gmail (#1786): foto, quem escreveu de verdade,
// selos, "para…" com os detalhes, data no fuso da conta, o corpo limpo, a citação
// atrás de "•••", "Exibir toda a mensagem", tradução e anexos. Tudo o que o balão
// de e-mail de sempre faz continua aqui; muda só o desenho.
// Com "Recolher mensagens antigas" ligado, os e-mails antes do último viram uma linha
// (clicar abre). Por padrão ficam abertos (Rodrigo, 17/10).
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { Letter } from 'vue-letter';
import { sanitizeTextForRender } from '@chatwoot/utils';
import { allowedCssProperties } from 'lettersanitizer';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import FormattedContent from 'next/message/bubbles/Text/FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { EmailQuoteExtractor } from 'dashboard/helper/emailQuoteExtractor.js';
import { useTranslations } from 'dashboard/composables/useTranslations';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../../message/provider.js';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants.js';
import { useAgora } from '../useAgora';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  MODOS_DE_RESPOSTA,
  RESPONDER_EMAIL,
  useEmailDaConversa,
} from './useConversaDeEmail';
import {
  dataCompletaDoEmail,
  dataCurtaDoEmail,
  destinatariosDoEmail,
  lerEndereco,
  nomeCurto,
  remetenteDoEmail,
  semRastreio,
} from './dadosDoEmail';
import { CARTAO, COR_DO_SELO, SELO } from './visualEmail';
import MenuDoEmail from './MenuDoEmail.vue';

const ALTURA_LONGA = 400;

const {
  id,
  content,
  contentAttributes,
  attachments,
  messageType,
  sender,
  createdAt,
  inboxId,
  status,
} = useMessageContext();
const { t, locale } = useI18n();
const email = useEmailDaConversa();
const agora = useAgora();
const caixaPorId = useMapGetter('inboxes/getInbox');

const recebido = computed(() => messageType.value === MESSAGE_TYPES.INCOMING);
const enviado = computed(() => messageType.value === MESSAGE_TYPES.OUTGOING);
const caixa = computed(() => caixaPorId.value(inboxId.value) || {});

const remetente = computed(() => {
  const real = remetenteDoEmail({
    contentAttributes: contentAttributes.value,
    sender: sender.value,
    recebido: recebido.value,
  });
  // Enviado pelo painel: o endereço é o da caixa.
  if (enviado.value && !contentAttributes.value?.email?.from) {
    return { ...real, endereco: caixa.value.email || '' };
  }
  return real;
});

const ehAgente = computed(
  () =>
    Boolean(contentAttributes.value?.autonomiaAgentId) ||
    sender.value?.type === 'agent_bot'
);
const ehAviso = computed(() =>
  Boolean(contentAttributes.value?.crmBookingNotice)
);
const ehCliente = computed(
  () =>
    recebido.value &&
    !remetente.value.emCopia &&
    sender.value?.contact_type === 'customer'
);
const falhou = computed(() => status.value === MESSAGE_STATUS.FAILED);

const nomeMostrado = computed(() =>
  ehAgente.value
    ? t('CONVERSA_CANAL.REMETENTE.AGENTE_COM_NOME', {
        nome: remetente.value.nome,
      })
    : remetente.value.nome
);

const destinos = computed(() => destinatariosDoEmail(contentAttributes.value));
const enderecoDaCaixa = computed(() => (caixa.value.email || '').toLowerCase());
const curtoOuMim = texto =>
  lerEndereco(texto).endereco.toLowerCase() === enderecoDaCaixa.value
    ? t('CONVERSA_CANAL.EMAIL.MIM')
    : nomeCurto(texto);
const resumoPara = computed(() => {
  const nomes = [...destinos.value.para, ...destinos.value.cc].map(curtoOuMim);
  if (!nomes.length) return '';
  return t('CONVERSA_CANAL.EMAIL.PARA_RESUMO', { nomes: nomes.join(', ') });
});

const fuso = computed(() => email.fuso.value);
const idioma = computed(() => idiomaDoPainel(locale.value));
const dataCurta = computed(() =>
  dataCurtaDoEmail({
    quando: createdAt.value,
    agora: agora.value,
    fuso: fuso.value,
    idioma: idioma.value,
  })
);
const dataCompleta = computed(() =>
  dataCompletaDoEmail({
    quando: createdAt.value,
    agora: agora.value,
    fuso: fuso.value,
    idioma: idioma.value,
  })
);

// Corpo: o mesmo caminho do balão de sempre (HTML do remetente pelo Letter, que
// sanitiza; texto puro escapado; o que o painel escreveu em markdown).
const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);
const verOriginal = ref(false);
const textoOriginal = computed(() =>
  sanitizeTextForRender(
    contentAttributes.value?.email?.textContent?.full ?? content.value
  )
);
const htmlOriginal = computed(
  () => contentAttributes.value?.email?.htmlContent?.full || textoOriginal.value
);
const temEmail = computed(
  () =>
    contentAttributes.value?.email?.textContent?.full ||
    contentAttributes.value?.email?.htmlContent?.full
);
const traduzido = computed(() => hasTranslations.value && !verOriginal.value);
const htmlCompleto = computed(() =>
  traduzido.value ? translationContent.value : htmlOriginal.value
);
const textoDoLetter = computed(() =>
  traduzido.value ? translationContent.value : textoOriginal.value
);
const conteudoDoPainel = computed(() =>
  traduzido.value ? translationContent.value : content.value
);
const htmlSemCitacao = computed(() =>
  EmailQuoteExtractor.extractQuotes(htmlCompleto.value)
);
const temCitacao = computed(() =>
  EmailQuoteExtractor.hasQuotes(htmlCompleto.value)
);
const verCitacao = ref(false);
const CSS_PERMITIDO = [
  ...allowedCssProperties,
  'transform',
  'transform-origin',
];

const corpo = useTemplateRef('corpo');
const longo = ref(false);
const inteiro = ref(false);
onMounted(() => {
  longo.value = (corpo.value?.scrollHeight || 0) > ALTURA_LONGA;
});

// Recolhido só com a opção ligada, e nunca o último e-mail.
const abertoAqui = ref(false);
const recolhido = computed(
  () =>
    email.recolher.value &&
    id.value !== email.ultimoEmailId.value &&
    !abertoAqui.value
);
// Uma linha do começo do e-mail, sem as marcas de negrito do texto escrito no painel.
const trecho = computed(() =>
  String(
    contentAttributes.value?.email?.textContent?.reply ||
      textoOriginal.value ||
      ''
  )
    .split('**')
    .join('')
    .split('__')
    .join('')
    .split('\n')
    .map(linha => linha.trim())
    .filter(Boolean)
    .join(' ')
);

const verDetalhes = ref(false);
// Responder (à vista) e o menu ⋮ (Responder a todos, Encaminhar) partem deste e-mail.
const responder = (modo = MODOS_DE_RESPOSTA.RESPONDER) =>
  emitter.emit(RESPONDER_EMAIL, { modo, mensagemId: id.value });
</script>

<template>
  <article
    :class="[CARTAO, recolhido ? 'py-3' : 'py-5']"
    data-cartao-do-email
    :data-recolhido="recolhido || undefined"
  >
    <!-- Recolhido: uma linha, como no leitor de e-mail; clicar abre. -->
    <button
      v-if="recolhido"
      type="button"
      class="flex items-center gap-3 w-full min-h-11 px-2 sm:px-4 text-start rounded-lg hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="t('CONVERSA_CANAL.EMAIL.ABRIR', { nome: nomeMostrado })"
      @click="abertoAqui = true"
    >
      <Avatar
        :name="remetente.nome"
        :src="remetente.foto"
        :size="32"
        rounded-full
      />
      <span
        class="flex items-center gap-1.5 max-w-[40%] sm:max-w-none sm:w-44 flex-shrink-0 min-w-0 text-sm font-semibold text-n-slate-12"
      >
        <span class="truncate">{{ nomeMostrado }}</span>
        <span
          v-if="remetente.emCopia"
          class="font-medium"
          :class="[SELO, COR_DO_SELO.copia]"
        >
          {{ t('CONVERSA_CANAL.EMAIL.SELO_COPIA') }}
        </span>
      </span>
      <span class="flex-1 min-w-0 truncate text-sm text-n-slate-11">
        {{ trecho }}
      </span>
      <time
        class="flex-shrink-0 text-xs text-n-slate-11 tabular-nums"
        :title="dataCompleta"
      >
        {{ dataCurta }}
      </time>
    </button>

    <template v-else>
      <header class="flex items-start gap-3 px-2 sm:px-4">
        <Avatar
          :name="remetente.nome"
          :src="remetente.foto"
          :size="40"
          rounded-full
          class="flex-shrink-0"
        />
        <div class="flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span class="text-sm font-semibold text-n-slate-12 break-words">
              {{ nomeMostrado }}
            </span>
            <span
              v-if="remetente.endereco && remetente.endereco !== nomeMostrado"
              class="text-xs text-n-slate-11 break-all"
            >
              &lt;{{ remetente.endereco }}&gt;
            </span>
            <span v-if="ehCliente" :class="[SELO, COR_DO_SELO.cliente]">
              {{ t('CONVERSA_CANAL.EMAIL.SELO_CLIENTE') }}
            </span>
            <span
              v-if="remetente.emCopia"
              :class="[SELO, COR_DO_SELO.copia]"
              :title="t('CONVERSA_CANAL.EMAIL.SELO_COPIA_DICA')"
            >
              {{ t('CONVERSA_CANAL.EMAIL.SELO_COPIA') }}
            </span>
            <span v-if="ehAviso" :class="[SELO, COR_DO_SELO.aviso]">
              <Icon icon="i-lucide-calendar-clock" class="size-3" />
              {{ t('CONVERSA_CANAL.EMAIL.SELO_AVISO') }}
            </span>
            <span v-if="falhou" :class="[SELO, COR_DO_SELO.falha]">
              {{ t('CONVERSA_CANAL.EMAIL.SELO_FALHA') }}
            </span>
          </div>
          <button
            v-if="resumoPara"
            type="button"
            class="inline-flex items-center gap-0.5 mt-0.5 -ms-1 px-1 min-h-6 rounded text-xs text-n-slate-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-expanded="verDetalhes"
            :aria-label="t('CONVERSA_CANAL.EMAIL.MOSTRAR_DETALHES')"
            @click="verDetalhes = !verDetalhes"
          >
            <span class="truncate max-w-[18rem] sm:max-w-[28rem]">
              {{ resumoPara }}
            </span>
            <Icon
              :icon="
                verDetalhes ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
              class="size-3.5 flex-shrink-0"
            />
          </button>
          <dl
            v-if="verDetalhes"
            class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1 mt-2 p-3 rounded-lg border border-n-weak bg-n-alpha-1 text-xs"
            data-detalhes-do-email
          >
            <dt class="text-n-slate-11 text-end">
              {{ t('CONVERSA_CANAL.EMAIL.DE') }}
            </dt>
            <dd class="text-n-slate-12 break-all">
              {{ remetente.nome }} &lt;{{ remetente.endereco }}&gt;
            </dd>
            <template v-if="destinos.para.length">
              <dt class="text-n-slate-11 text-end">
                {{ t('CONVERSA_CANAL.EMAIL.PARA') }}
              </dt>
              <dd class="text-n-slate-12 break-all">
                {{ destinos.para.join(', ') }}
              </dd>
            </template>
            <template v-if="destinos.cc.length">
              <dt class="text-n-slate-11 text-end">
                {{ t('CONVERSA_CANAL.EMAIL.CC') }}
              </dt>
              <dd class="text-n-slate-12 break-all">
                {{ destinos.cc.join(', ') }}
              </dd>
            </template>
            <template v-if="destinos.cco.length">
              <dt class="text-n-slate-11 text-end">
                {{ t('CONVERSA_CANAL.EMAIL.CCO') }}
              </dt>
              <dd class="text-n-slate-12 break-all">
                {{ destinos.cco.join(', ') }}
              </dd>
            </template>
            <dt class="text-n-slate-11 text-end">
              {{ t('CONVERSA_CANAL.EMAIL.DATA') }}
            </dt>
            <dd class="text-n-slate-12">{{ dataCompleta }}</dd>
            <template v-if="contentAttributes?.email?.subject">
              <dt class="text-n-slate-11 text-end">
                {{ t('CONVERSA_CANAL.EMAIL.ASSUNTO') }}
              </dt>
              <dd class="text-n-slate-12 break-words">
                {{ contentAttributes.email.subject }}
              </dd>
            </template>
          </dl>
        </div>
        <div class="flex items-center gap-1 flex-shrink-0">
          <time
            class="text-xs text-n-slate-11 tabular-nums whitespace-nowrap"
            :title="dataCompleta"
          >
            {{ dataCurta }}
          </time>
          <button
            type="button"
            class="grid place-content-center size-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="t('CONVERSA_CANAL.EMAIL.RESPONDER')"
            :title="t('CONVERSA_CANAL.EMAIL.RESPONDER')"
            data-responder-este
            @click="responder()"
          >
            <Icon icon="i-lucide-reply" class="size-4" />
          </button>
          <MenuDoEmail @escolher="responder" />
        </div>
      </header>

      <section class="mt-3 ps-[60px] sm:ps-[68px] pe-2 sm:pe-4">
        <div
          ref="corpo"
          class="relative text-sm text-n-slate-12"
          :class="{ 'max-h-[400px] overflow-hidden': longo && !inteiro }"
          data-corpo-do-email
        >
          <FormattedContent
            v-if="enviado && content && !temEmail"
            :content="conteudoDoPainel"
          />
          <Letter
            v-else
            :key="`${verCitacao ? 'c' : 's'}-${traduzido ? 't' : 'o'}`"
            class-name="prose prose-bubble !max-w-none letter-render"
            :allowed-css-properties="CSS_PERMITIDO"
            :html="verCitacao ? htmlCompleto : htmlSemCitacao"
            :text="textoDoLetter"
            :rewrite-external-resources="semRastreio"
            :rewrite-external-links="semRastreio"
          />
          <div
            v-if="longo && !inteiro"
            class="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-n-surface-1 to-transparent"
          />
        </div>
        <button
          v-if="longo && !inteiro"
          type="button"
          class="mt-2 min-h-11 text-sm font-medium text-n-blue-11 hover:underline"
          @click="inteiro = true"
        >
          {{ t('CONVERSA_CANAL.EMAIL.EXIBIR_TUDO') }}
        </button>
        <button
          v-if="temCitacao"
          type="button"
          class="inline-flex items-center justify-center mt-2 h-5 px-2 rounded-full bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-expanded="verCitacao"
          :aria-label="
            verCitacao
              ? t('CONVERSA_CANAL.EMAIL.ESCONDER_CITACAO')
              : t('CONVERSA_CANAL.EMAIL.MOSTRAR_CITACAO')
          "
          :title="
            verCitacao
              ? t('CONVERSA_CANAL.EMAIL.ESCONDER_CITACAO')
              : t('CONVERSA_CANAL.EMAIL.MOSTRAR_CITACAO')
          "
          data-citacao-do-email
          @click="verCitacao = !verCitacao"
        >
          <Icon icon="i-lucide-ellipsis" class="size-4" />
        </button>
        <TranslationToggle
          v-if="hasTranslations"
          class="mt-2"
          :showing-original="verOriginal"
          @toggle="verOriginal = !verOriginal"
        />
        <div
          v-if="Array.isArray(attachments) && attachments.length"
          class="mt-4 pt-3 border-t border-n-weak"
          data-anexos-do-email
        >
          <p class="mb-2 text-xs font-medium text-n-slate-11">
            {{
              t(
                'CONVERSA_CANAL.EMAIL.ANEXOS',
                { total: attachments.length },
                attachments.length
              )
            }}
          </p>
          <AttachmentChips :attachments="attachments" class="gap-2" />
        </div>
      </section>
    </template>
  </article>
</template>
