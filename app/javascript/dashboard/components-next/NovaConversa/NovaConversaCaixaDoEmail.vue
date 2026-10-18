<script setup>
// #1809 — a caixa "Mensagem" do e-mail na gaveta "Escrever", no padrão da resposta de
// e-mail nova (#1786): no topo, para quem vai e Cc/Cco num toque (CampoDeEnderecos);
// o texto, que nasce compacto e cresce com o conteúdo; o modelo de e-mail escolhido no
// "+" (ModeloDaResposta), embaixo do texto; os anexos; e no pé, fixa, a barra (com o
// aviso de assinatura logo acima). Passando do teto, o conteúdo rola por dentro, sem levar
// a gaveta junto, e a barra fica fora da rolagem: sempre à vista e sem cobrir o cursor.
// A régua de formatação fica atrás do "Aa".
import { computed, ref } from 'vue';
import WootEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import AvisoDeAssinatura from 'dashboard/components-next/conversa-canal/email/AvisoDeAssinatura.vue';
import CampoDeEnderecos from 'dashboard/components-next/conversa-canal/email/CampoDeEnderecos.vue';
import ModeloDaResposta from 'dashboard/components-next/conversa-canal/email/ModeloDaResposta.vue';
import { FORMATACAO_FIXA } from 'dashboard/components-next/conversa-canal/email/visualEmail';
import NovaConversaBarraDoEmail from './NovaConversaBarraDoEmail.vue';

const props = defineProps({
  canal: { type: Object, required: true },
  assinatura: { type: String, default: '' },
  comAssinatura: { type: Boolean, default: false },
  // { nome, email } do contato escolhido.
  para: { type: Object, default: null },
  // O modelo de e-mail da gaveta (useModeloDoEmailNaGaveta); null: sem modelos.
  modelo: { type: Object, default: null },
});

const mensagem = defineModel('mensagem', { type: String, default: '' });
const cc = defineModel('cc', { type: String, default: '' });
const bcc = defineModel('bcc', { type: String, default: '' });
const anexos = defineModel('anexos', { type: Array, default: () => [] });

// Emoji e ditado entram no ponto do cursor do editor; o editor zera depois.
const inserir = ref('');
const formatacao = ref(false);
// Cópia já preenchida (rascunho de antes) nasce aberta: ninguém envia cópia sem ver.
const verCc = ref(Boolean(cc.value));
const verCco = ref(Boolean(bcc.value));

const enderecoDoPara = computed(() =>
  props.para?.email ? `<${props.para.email}>` : ''
);

const LINK =
  'min-h-11 px-3 rounded-full text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
// O texto: placeholder no topo, nasce com umas 6 linhas e cresce sem rolar sozinho (quem
// rola é a caixa). O teto da caixa é a altura da gaveta menos o cabeçalho e o rodapé.
const EDITOR =
  '[&_.ProseMirror-woot-style]:!min-h-[8.5rem] [&_.ProseMirror-woot-style]:!max-h-none [&_.ProseMirror-woot-style]:!overflow-visible';
</script>

<template>
  <div
    role="group"
    aria-labelledby="nova-conversa-email-rotulo"
    class="flex max-h-[calc(100dvh-19rem)] flex-col rounded-2xl border border-n-weak bg-n-surface-1 shadow-[0_1px_2px_rgba(0,0,0,0.12),0_1px_3px_1px_rgba(0,0,0,0.06)] transition focus-within:border-n-blue-8"
    :class="formatacao ? FORMATACAO_FIXA : ''"
    data-caixa-do-email
  >
    <div
      class="min-h-0 flex-1 overflow-y-auto overscroll-contain [overflow-anchor:none]"
      data-rolagem-do-email
    >
      <div class="flex flex-col px-3">
        <div
          class="flex min-h-11 items-center gap-2 border-b border-n-weak ps-1 text-sm"
          data-para-do-email
        >
          <span class="w-12 flex-shrink-0 text-n-slate-11">
            {{ $t('CONVERSA_CANAL.EMAIL.PARA') }}
          </span>
          <span class="min-w-0 flex-1 truncate text-n-slate-12">
            {{ para?.nome }}
            <span class="text-n-slate-11">{{ enderecoDoPara }}</span>
          </span>
          <button
            v-if="!verCc"
            type="button"
            :class="LINK"
            data-abrir-cc
            @click="verCc = true"
          >
            {{ $t('CONVERSA_CANAL.EMAIL.CC') }}
          </button>
          <button
            v-if="!verCco"
            type="button"
            :class="LINK"
            data-abrir-cco
            @click="verCco = true"
          >
            {{ $t('CONVERSA_CANAL.EMAIL.CCO') }}
          </button>
        </div>
        <CampoDeEnderecos
          v-if="verCc"
          v-model="cc"
          :rotulo="$t('CONVERSA_CANAL.EMAIL.CC')"
          data-campo-cc
        />
        <CampoDeEnderecos
          v-if="verCco"
          v-model="bcc"
          :rotulo="$t('CONVERSA_CANAL.EMAIL.CCO')"
          data-campo-cco
        />
      </div>

      <div class="px-4 pt-3" :class="EDITOR">
        <WootEditor
          v-model="mensagem"
          class="popover-prosemirror-menu"
          :editor-id="`nova-conversa-email-${canal.id}`"
          :placeholder="
            $t('COMPOSE_NEW_CONVERSATION.FORM.MESSAGE_EDITOR.PLACEHOLDER')
          "
          :focus-on-mount="false"
          enable-variables
          enable-captain-tools
          :signature="assinatura"
          allow-signature
          :send-with-signature="comAssinatura"
          :channel-type="canal.channelType"
          :medium="canal.medium || ''"
          :update-selection-with="inserir"
          @clear-selection="inserir = ''"
        />
      </div>

      <div v-if="modelo?.modelo.value" class="px-3">
        <ModeloDaResposta
          :modelo="modelo.modelo.value"
          :valores="modelo.valores.value"
          @campo="modelo.campo"
          @tirar="modelo.tirar"
        />
      </div>

      <AttachmentPreviews
        v-if="anexos.length"
        v-model:attachments="anexos"
        class="!px-4 !pt-2 !pb-3"
        data-anexos-do-email
      />
    </div>

    <div
      class="flex-shrink-0 rounded-b-2xl border-t border-n-weak bg-n-surface-1"
      data-pe-do-email
    >
      <div v-if="comAssinatura && !assinatura" class="px-3 pt-2">
        <AvisoDeAssinatura />
      </div>
      <NovaConversaBarraDoEmail
        v-model:anexos="anexos"
        v-model:formatacao="formatacao"
        :canal="canal"
        :com-assinatura="comAssinatura"
        :com-modelos="Boolean(modelo)"
        @inserir="texto => (inserir = texto)"
        @modelo="id => modelo?.escolher(id)"
      />
    </div>
  </div>
</template>
