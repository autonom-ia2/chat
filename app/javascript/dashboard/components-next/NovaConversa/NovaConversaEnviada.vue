<script setup>
import PreviaWhatsapp from 'dashboard/components-next/whatsapp-preview/PreviaWhatsapp.vue';
import NovaConversaCartaoEmail from './NovaConversaCartaoEmail.vue';

// #1459 — depois de enviar: o visto verde, o que foi enviado e por onde. No
// e-mail, o cartão com assunto e corpo; nos outros canais, o balão. O título
// ("Mensagem a caminho para …") está no herói, e os botões ("Abrir a conversa"
// e "Fechar"), no rodapé da gaveta.
defineProps({
  texto: { type: String, default: '' },
  email: { type: Boolean, default: false },
  assunto: { type: String, default: '' },
  chaveDoCanal: { type: String, default: 'OUTRO' },
  caixa: { type: String, default: '' },
  endereco: { type: String, default: '' },
  // #1505 — o número da conversa em que a mensagem entrou, quando ela já
  // existia.
  numero: { type: Number, default: null },
});
</script>

<template>
  <div
    data-nova-conversa-enviada
    role="status"
    class="mx-auto flex w-full max-w-md flex-col items-center gap-5 px-5 py-12"
  >
    <span
      class="grid size-16 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-8" />
    </span>
    <NovaConversaCartaoEmail
      v-if="email"
      :remetente="caixa"
      :endereco="endereco"
      :assunto="assunto"
      :corpo="texto"
    />
    <PreviaWhatsapp
      v-else-if="texto.trim()"
      class="w-full"
      :texto="texto"
      :nome-do-remetente="caixa"
      :hora="$t('NOVA_CONVERSA.PREVIA.AGORA')"
    />
    <p
      data-nova-conversa-enviada-canal
      class="mb-0 text-center text-[0.9375rem] text-n-slate-11"
    >
      {{ $t(`NOVA_CONVERSA.ENVIADA.PELO.${chaveDoCanal}`, { caixa }) }}
    </p>
    <p
      v-if="numero"
      data-nova-conversa-enviada-na-conversa
      class="mb-0 text-center text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('NOVA_CONVERSA.ENVIADA.NA_CONVERSA', { numero }) }}
    </p>
  </div>
</template>
