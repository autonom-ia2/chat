<script setup>
import PreviaMoldura from 'dashboard/routes/dashboard/crm/components/funil/previas/PreviaMoldura.vue';
import PreviaWhatsapp from 'dashboard/components-next/whatsapp-preview/PreviaWhatsapp.vue';

// #1459 — a coluna da direita: como a pessoa recebe a mensagem, ao vivo. No
// e-mail é um cartão de e-mail; nos outros canais, o balão.
defineProps({
  nome: { type: String, default: '' },
  email: { type: Boolean, default: false },
  texto: { type: String, default: '' },
  assunto: { type: String, default: '' },
  remetente: { type: String, default: '' },
  enderecoDoRemetente: { type: String, default: '' },
});

const P = 'NOVA_CONVERSA.PREVIA';
</script>

<template>
  <PreviaMoldura
    class="lg:sticky lg:top-7"
    :titulo="nome ? $t(`${P}.TITULO`, { nome }) : $t(`${P}.TITULO_SEM_NOME`)"
  >
    <article
      v-if="email"
      data-nova-conversa-previa-email
      class="flex flex-col rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    >
      <dl class="m-0 flex flex-col gap-1 border-b border-n-weak p-4 text-sm">
        <div class="flex gap-2">
          <dt class="shrink-0 font-normal text-n-slate-11">
            {{ $t(`${P}.DE`) }}
          </dt>
          <dd class="m-0 min-w-0 break-words text-n-slate-12">
            {{ remetente }}
            <span v-if="enderecoDoRemetente" class="text-n-slate-11">
              ({{ enderecoDoRemetente }})
            </span>
          </dd>
        </div>
        <div class="flex gap-2">
          <dt class="shrink-0 font-normal text-n-slate-11">
            {{ $t(`${P}.ASSUNTO`) }}
          </dt>
          <dd
            class="m-0 min-w-0 break-words font-semibold"
            :class="assunto.trim() ? 'text-n-slate-12' : 'text-n-slate-10'"
          >
            {{ assunto.trim() || $t(`${P}.SEM_ASSUNTO`) }}
          </dd>
        </div>
      </dl>
      <p
        class="mb-0 min-h-24 whitespace-pre-wrap break-words p-4 text-sm leading-relaxed"
        :class="texto.trim() ? 'text-n-slate-12' : 'text-n-slate-10'"
      >
        {{ texto.trim() ? texto : $t(`${P}.FANTASMA`) }}
      </p>
    </article>
    <PreviaWhatsapp
      v-else
      :texto="texto"
      :nome-do-remetente="remetente"
      :fantasma="$t(`${P}.FANTASMA`)"
    />
  </PreviaMoldura>
</template>
