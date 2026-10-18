<script setup>
// Topo da conversa de e-mail (#1786): o assunto do e-mail uma vez, grande, como no
// leitor de e-mail, e a opção de recolher as mensagens antigas (por padrão abertas;
// a escolha fica guardada para cada atendente).
// O assunto do FUNIL (CRM) é outra coisa e continua no seletor da caixa de resposta.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useEmailDaConversa } from './useConversaDeEmail';

const { t } = useI18n();
const email = useEmailDaConversa();
</script>

<template>
  <li
    class="list-none w-full max-w-[960px] mx-auto flex flex-wrap items-start justify-between gap-x-4 gap-y-2 pt-4 pb-3 px-2 sm:px-4 border-b border-n-weak"
    data-topo-do-email
  >
    <h2
      class="basis-full sm:basis-0 flex-1 min-w-0 text-[22px] leading-7 font-normal text-n-slate-12 break-words [text-wrap:balance]"
    >
      {{ email.assunto.value || t('CONVERSA_CANAL.EMAIL.SEM_ASSUNTO') }}
    </h2>
    <button
      type="button"
      class="inline-flex items-center gap-1.5 min-h-11 px-3 rounded-full text-sm text-n-slate-11 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-pressed="email.recolher.value"
      data-recolher-antigas
      @click="email.alternarRecolher"
    >
      <Icon
        :icon="
          email.recolher.value
            ? 'i-lucide-unfold-vertical'
            : 'i-lucide-fold-vertical'
        "
        class="size-4"
      />
      {{
        email.recolher.value
          ? t('CONVERSA_CANAL.EMAIL.ABRIR_TODAS')
          : t('CONVERSA_CANAL.EMAIL.RECOLHER_ANTIGAS')
      }}
    </button>
  </li>
</template>
