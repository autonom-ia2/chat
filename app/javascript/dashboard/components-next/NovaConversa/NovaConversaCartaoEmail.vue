<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { SINAIS } from './modeloPronto';
import { htmlDePrevia } from 'dashboard/components-next/conversa-canal/email/modeloDeEmail';

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
  </article>
</template>
