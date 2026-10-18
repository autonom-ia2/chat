<script setup>
// Faixa fina sobre a caixa de resposta da conversa de e-mail nova (#1786): diz o que
// está sendo escrito e fecha a caixa, devolvendo a tela à leitura. O rascunho fica
// guardado (o Chatwoot já salva) e volta ao apertar Responder de novo.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useEmailDaConversa } from './useConversaDeEmail';

const { t } = useI18n();
const email = useEmailDaConversa();
</script>

<template>
  <div
    v-if="email.ligado.value && email.respostaAberta.value"
    class="flex justify-end w-[calc(100%-1rem)] max-w-[960px] mx-auto pt-2"
    data-fechar-resposta
  >
    <button
      type="button"
      class="inline-flex items-center gap-1.5 min-h-9 px-3 rounded-full text-sm text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="email.fecharResposta"
    >
      <Icon icon="i-lucide-x" class="size-4" />
      {{ t('CONVERSA_CANAL.EMAIL.FECHAR_RESPOSTA') }}
    </button>
  </div>
</template>
