<script setup>
import { computed, inject, ref } from 'vue';
import MessageEditor from 'dashboard/components-next/NewConversation/components/MessageEditor.vue';
import EmailOptions from 'dashboard/components-next/NewConversation/components/EmailOptions.vue';
import NovaConversaCaixaDoEmail from './NovaConversaCaixaDoEmail.vue';
import { EMAIL_DA_GAVETA } from './useModeloDoEmailNaGaveta';

// #1459 — e-mail: "Assunto" e a mensagem (com formatação e assinatura, pelo
// editor que a tela antiga já usava). Cópia para outras pessoas fica atrás de
// "Mais opções", para não pesar em quem só quer escrever.
defineProps({
  canal: { type: Object, required: true },
  assinatura: { type: String, default: '' },
  comAssinatura: { type: Boolean, default: false },
  // #1505 — continuando uma conversa, o assunto é o dela: sem campo.
  comAssunto: { type: Boolean, default: true },
  // #1809 — caixa com a conversa de e-mail nova: a caixa da resposta de e-mail
  // (NovaConversaCaixaDoEmail), com Cc/Cco no topo, régua no "Aa", modelo de
  // e-mail e a barra de baixo fixa.
  barraNova: { type: Boolean, default: false },
});

const assunto = defineModel('assunto', { type: String, default: '' });
const mensagem = defineModel('mensagem', { type: String, default: '' });
const cc = defineModel('cc', { type: String, default: '' });
const bcc = defineModel('bcc', { type: String, default: '' });
const anexos = defineModel('anexos', { type: Array, default: () => [] });

// O modelo de e-mail e o destinatário vêm da gaveta (provide); fora dela, nada.
const daGaveta = inject(EMAIL_DA_GAVETA, null);
const para = computed(() => daGaveta?.para.value ?? null);

const P = 'NOVA_CONVERSA.MENSAGEM';
// Com cópia já preenchida (rascunho de antes), as opções nascem abertas:
// ninguém envia cópia sem ver para quem.
const maisOpcoes = ref(Boolean(cc.value || bcc.value));
</script>

<template>
  <div class="flex flex-col gap-5">
    <div v-if="comAssunto" class="flex flex-col gap-2">
      <label
        for="nova-conversa-assunto"
        class="mb-0 text-base font-semibold text-n-slate-12"
      >
        {{ $t(`${P}.ASSUNTO`) }}
      </label>
      <input
        id="nova-conversa-assunto"
        v-model="assunto"
        data-foco
        type="text"
        autocomplete="off"
        :placeholder="$t(`${P}.ASSUNTO_PLACEHOLDER`)"
        class="reset-base !mb-0 min-h-12 w-full rounded-2xl border border-n-weak bg-n-solid-1 px-4 text-base text-n-slate-12 shadow-sm outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8 focus:shadow-md"
      />
    </div>

    <div class="flex flex-col gap-2">
      <span
        id="nova-conversa-email-rotulo"
        class="text-base font-semibold text-n-slate-12"
      >
        {{ $t(`${P}.CORPO`) }}
      </span>
      <NovaConversaCaixaDoEmail
        v-if="barraNova"
        v-model:mensagem="mensagem"
        v-model:cc="cc"
        v-model:bcc="bcc"
        v-model:anexos="anexos"
        :canal="canal"
        :assinatura="assinatura"
        :com-assinatura="comAssinatura"
        :para="para"
        :da-gaveta="daGaveta"
      />
      <div
        v-else
        role="group"
        aria-labelledby="nova-conversa-email-rotulo"
        class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm transition focus-within:border-n-blue-8 focus-within:shadow-md hover:border-n-slate-7"
      >
        <MessageEditor
          v-model="mensagem"
          :message-signature="assinatura"
          :send-with-signature="comAssinatura"
          :channel-type="canal.channelType"
          :medium="canal.medium || ''"
        />
      </div>
    </div>

    <div v-if="!barraNova" class="flex flex-col items-start gap-3">
      <button
        type="button"
        data-nova-conversa-mais
        :aria-expanded="maisOpcoes"
        aria-controls="nova-conversa-copias"
        class="-ms-2 inline-flex min-h-11 items-center gap-2 rounded-xl px-2 text-sm font-medium text-n-slate-11 transition hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="maisOpcoes = !maisOpcoes"
      >
        <span
          class="size-4"
          :class="maisOpcoes ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          aria-hidden="true"
        />
        {{ $t(maisOpcoes ? `${P}.MENOS_OPCOES` : `${P}.MAIS_OPCOES`) }}
      </button>
      <!-- O EmailOptions traz também o assunto na primeira linha; aqui ele já
           tem campo próprio, então só as cópias aparecem. -->
      <div
        v-if="maisOpcoes"
        id="nova-conversa-copias"
        class="w-full rounded-2xl border border-n-weak bg-n-solid-1"
      >
        <EmailOptions
          v-model:subject="assunto"
          v-model:cc-emails="cc"
          v-model:bcc-emails="bcc"
          :contacts="[]"
          class="[&>div:first-child]:hidden"
        />
      </div>
    </div>
  </div>
</template>
