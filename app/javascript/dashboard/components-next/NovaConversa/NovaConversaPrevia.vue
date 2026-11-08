<script setup>
import PreviaMoldura from 'dashboard/routes/dashboard/crm/components/funil/previas/PreviaMoldura.vue';
import PreviaWhatsapp from 'dashboard/components-next/whatsapp-preview/PreviaWhatsapp.vue';
import NovaConversaCartaoEmail from './NovaConversaCartaoEmail.vue';

// #1459 — a coluna da direita: como a pessoa recebe a mensagem, ao vivo. No
// e-mail é um cartão de e-mail; nos outros canais, o balão.
defineProps({
  nome: { type: String, default: '' },
  email: { type: Boolean, default: false },
  texto: { type: String, default: '' },
  assunto: { type: String, default: '' },
  remetente: { type: String, default: '' },
  enderecoDoRemetente: { type: String, default: '' },
  // #1809: o modelo de e-mail preenchido (campo vazio destacado), embaixo do texto.
  modeloHtml: { type: String, default: '' },
  // #1809: o e-mail citado no fim, ao continuar a conversa (null: sem histórico).
  historico: { type: Object, default: null },
  // #1988: o que vai anexado no WhatsApp (a gravação e os arquivos), embaixo do balão.
  anexos: { type: Array, default: () => [] },
});

const nomeDoAnexo = anexo =>
  anexo.resource?.filename || anexo.resource?.name || '';

const P = 'NOVA_CONVERSA.PREVIA';
</script>

<template>
  <PreviaMoldura
    class="lg:sticky lg:top-7"
    :titulo="nome ? $t(`${P}.TITULO`, { nome }) : $t(`${P}.TITULO_SEM_NOME`)"
  >
    <NovaConversaCartaoEmail
      v-if="email"
      :remetente="remetente"
      :endereco="enderecoDoRemetente"
      :assunto="assunto"
      :corpo="texto"
      :fantasma="$t(`${P}.FANTASMA`)"
      :modelo-html="modeloHtml"
      :historico="historico"
    />
    <template v-else>
      <PreviaWhatsapp
        :texto="texto"
        :nome-do-remetente="remetente"
        :fantasma="$t(`${P}.FANTASMA`)"
        :hora="$t(`${P}.AGORA`)"
      />
      <ul
        v-if="anexos.length"
        class="m-0 mt-3 flex list-none flex-col gap-2 p-0"
        data-previa-anexos
      >
        <li
          v-for="anexo in anexos"
          :key="anexo.resource?.id"
          class="flex min-w-0 items-center gap-2 rounded-xl bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-12"
        >
          <span
            class="size-4 shrink-0 text-n-slate-11"
            :class="
              anexo.isVoiceMessage ? 'i-ph-microphone-fill' : 'i-ph-paperclip'
            "
            aria-hidden="true"
          />
          <span class="min-w-0 truncate">
            {{
              anexo.isVoiceMessage
                ? $t('NOVA_CONVERSA.MENSAGEM.VOZ')
                : nomeDoAnexo(anexo)
            }}
          </span>
        </li>
      </ul>
    </template>
  </PreviaMoldura>
</template>
