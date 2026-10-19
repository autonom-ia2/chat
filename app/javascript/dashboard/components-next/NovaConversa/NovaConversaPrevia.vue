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
});

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
    <PreviaWhatsapp
      v-else
      :texto="texto"
      :nome-do-remetente="remetente"
      :fantasma="$t(`${P}.FANTASMA`)"
      :hora="$t(`${P}.AGORA`)"
    />
  </PreviaMoldura>
</template>
