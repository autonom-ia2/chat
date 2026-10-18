<script setup>
// Destinatários da resposta na conversa de e-mail nova (#1786): Para sempre à vista
// (no Encaminhar vem vazio), Cc e Cco abrem num toque, cada endereço como etiqueta com
// sugestão dos contatos. Embaixo, o assunto que o e-mail vai levar (o servidor monta
// "Re: <assunto da conversa>"). Mesmo contrato do ReplyEmailHead (v-model dos três
// campos), então o envio é o de sempre. O tipo de resposta fica no TopoDaResposta.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CampoDeEnderecos from './CampoDeEnderecos.vue';
import { useEmailDaConversa } from './useConversaDeEmail';

const para = defineModel('toEmails', { type: String, default: '' });
const cc = defineModel('ccEmails', { type: String, default: '' });
const cco = defineModel('bccEmails', { type: String, default: '' });

const { t } = useI18n();
const email = useEmailDaConversa();

const verCc = ref(Boolean(cc.value));
const verCco = ref(Boolean(cco.value));
watch(cc, valor => {
  if (valor) verCc.value = true;
});
watch(cco, valor => {
  if (valor) verCco.value = true;
});

const assunto = computed(() =>
  email.assunto.value ? `Re: ${email.assunto.value}` : ''
);

const LINK =
  'min-h-9 px-2 rounded-full text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <div class="flex flex-col" data-cabeca-da-resposta>
    <CampoDeEnderecos
      v-model="para"
      :rotulo="t('CONVERSA_CANAL.EMAIL.PARA')"
      :placeholder="t('CONVERSA_CANAL.EMAIL.PARA_EXEMPLO')"
      data-campo-para
    >
      <div class="flex items-center flex-shrink-0">
        <button
          v-if="!verCc"
          type="button"
          :class="LINK"
          data-abrir-cc
          @click="verCc = true"
        >
          {{ t('CONVERSA_CANAL.EMAIL.CC') }}
        </button>
        <button
          v-if="!verCco"
          type="button"
          :class="LINK"
          data-abrir-cco
          @click="verCco = true"
        >
          {{ t('CONVERSA_CANAL.EMAIL.CCO') }}
        </button>
      </div>
    </CampoDeEnderecos>
    <CampoDeEnderecos
      v-if="verCc"
      v-model="cc"
      :rotulo="t('CONVERSA_CANAL.EMAIL.CC')"
      data-campo-cc
    />
    <CampoDeEnderecos
      v-if="verCco"
      v-model="cco"
      :rotulo="t('CONVERSA_CANAL.EMAIL.CCO')"
      data-campo-cco
    />
    <p
      v-if="assunto"
      class="flex items-center gap-2 min-h-10 px-1 border-b border-n-weak text-sm"
      data-assunto-da-resposta
    >
      <span class="w-16 flex-shrink-0 text-n-slate-11">
        {{ t('CONVERSA_CANAL.EMAIL.ASSUNTO_CURTO') }}
      </span>
      <span class="truncate text-n-slate-12">{{ assunto }}</span>
    </p>
  </div>
</template>
