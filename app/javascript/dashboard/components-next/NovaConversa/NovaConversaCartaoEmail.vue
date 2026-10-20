<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { SINAIS } from './modeloPronto';
import { htmlDePrevia } from 'dashboard/components-next/conversa-canal/email/modeloDeEmail';
import { Letter } from 'vue-letter';
import {
  remetenteDoEmail,
  semRastreio,
} from 'dashboard/components-next/conversa-canal/email/dadosDoEmail';
import {
  imagemSemRastreio,
  linkSemRastreio,
} from 'dashboard/components-next/conversa-canal/email/documentoDoEmail';
import { htmlDoTextoComImagens } from 'dashboard/components-next/conversa-canal/email/imagemNoTextoDoEmail';

// #1459 — um e-mail como cartão: de quem, assunto e corpo. Serve à prévia e à
// confirmação. O editor entrega o corpo com marcação de formatação; aqui ele
// aparece como texto limpo, tirado pelo formatador do próprio projeto (que
// interpreta a marcação e devolve só o texto), nunca como HTML cru.
const props = defineProps({
  remetente: { type: String, default: '' },
  endereco: { type: String, default: '' },
  assunto: { type: String, default: '' },
  corpo: { type: String, default: '' },
  // O que mostrar, apagado, enquanto o corpo está vazio.
  fantasma: { type: String, default: '' },
  // #1809: o modelo de e-mail, como o cliente vai ver (sem script, links sem clique).
  modeloHtml: { type: String, default: '' },
  // #1809: o e-mail citado no fim (histórico ao continuar a conversa), do store.
  historico: { type: Object, default: null },
});

const P = 'NOVA_CONVERSA.PREVIA';
const { getPlainText } = useMessageFormatter();

const texto = computed(() => getPlainText(props.corpo).trim());
const enderecoEntreParenteses = computed(
  () => `${SINAIS.abreParenteses}${props.endereco}${SINAIS.fechaParenteses}`
);

const ALTURA_MAXIMA = 520;
const moldura = useTemplateRef('moldura');
const altura = ref(320);
const modeloSemClique = computed(() => htmlDePrevia(props.modeloHtml));
const medir = () => {
  const total =
    moldura.value?.contentDocument?.documentElement?.scrollHeight || 0;
  if (total) altura.value = Math.min(ALTURA_MAXIMA, total);
};

// Quem escreveu o e-mail citado e o texto dele, como o cliente vê no fim do e-mail.
const quemCitou = computed(
  () =>
    remetenteDoEmail({
      contentAttributes: { email: props.historico?.content_attributes?.email },
      sender: props.historico?.sender,
      recebido: true,
    }).nome
);
const textoCitado = computed(() => {
  const email = props.historico?.content_attributes?.email || {};
  return String(
    email.text_content?.full || props.historico?.content || ''
  ).trim();
});
// #1942: imagem embutida pelo Chatwoot no texto puro aparece como imagem, pelo Letter
// (que sanitiza), nunca como tag crua. Sem imagem, o texto segue como texto.
const htmlCitado = computed(() => htmlDoTextoComImagens(textoCitado.value));
const imagemDaPrevia = imagemSemRastreio(semRastreio);
const linkDaPrevia = linkSemRastreio(semRastreio);
</script>

<template>
  <article
    data-nova-conversa-email
    class="flex w-full flex-col rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <dl class="m-0 flex flex-col gap-1 border-b border-n-weak p-4 text-sm">
      <div class="flex gap-2">
        <dt class="shrink-0 font-normal text-n-slate-11">
          {{ $t(`${P}.DE`) }}
        </dt>
        <dd class="m-0 min-w-0 break-words text-n-slate-12">
          {{ remetente }}
          <span v-if="endereco" class="text-n-slate-11">
            {{ enderecoEntreParenteses }}
          </span>
        </dd>
      </div>
      <div class="flex gap-2">
        <dt class="shrink-0 font-normal text-n-slate-11">
          {{ $t(`${P}.ASSUNTO`) }}
        </dt>
        <dd
          data-nova-conversa-email-assunto
          class="m-0 min-w-0 break-words font-semibold"
          :class="assunto.trim() ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ assunto.trim() || $t(`${P}.SEM_ASSUNTO`) }}
        </dd>
      </div>
    </dl>
    <p
      data-nova-conversa-email-corpo
      class="mb-0 min-h-24 whitespace-pre-wrap break-words p-4 text-sm leading-relaxed"
      :class="texto ? 'text-n-slate-12' : 'text-n-slate-10'"
    >
      {{ texto || (modeloHtml ? '' : fantasma) }}
    </p>
    <iframe
      v-if="modeloHtml"
      ref="moldura"
      :srcdoc="modeloSemClique"
      sandbox="allow-same-origin"
      class="block w-full rounded-b-2xl border-0 border-t border-solid border-n-weak bg-white"
      :style="{ height: `${altura}px` }"
      :title="$t('CONVERSA_CANAL.EMAIL.PREVIA_DO_MODELO')"
      data-previa-do-modelo-na-gaveta
      @load="medir"
    />
    <div
      v-if="historico"
      class="border-t border-n-weak p-4 text-sm"
      data-previa-do-historico
    >
      <p class="mb-2 text-n-slate-11">
        {{ $t(`${P}.HISTORICO`, { nome: quemCitou }) }}
      </p>
      <div
        v-if="htmlCitado"
        class="max-h-48 overflow-hidden whitespace-pre-wrap break-words border-s-2 border-n-slate-6 ps-3 text-n-slate-11 [&_img]:max-h-32 [&_img]:max-w-full [&_img]:object-contain"
        data-previa-do-historico-com-imagem
      >
        <Letter
          class-name="letter-render"
          :html="htmlCitado"
          :rewrite-external-resources="imagemDaPrevia"
          :rewrite-external-links="linkDaPrevia"
        />
      </div>
      <p
        v-else
        class="mb-0 max-h-48 overflow-hidden whitespace-pre-wrap break-words border-s-2 border-n-slate-6 ps-3 text-n-slate-11"
      >
        {{ textoCitado }}
      </p>
    </div>
  </article>
</template>
