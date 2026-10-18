<script setup>
// Um botão de modelo como o cliente vê (#1702). O de link abre, em outra aba, o
// endereço que o cliente recebeu (B2, Rodrigo em 17/10); os outros só mostram, com a
// dica de que o cliente toca no celular. Daqui não sai mensagem nenhuma.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

defineProps({
  // { tipo, texto, icone, endereco } (useModeloDaMensagem).
  botao: { type: Object, required: true },
  classe: { type: String, required: true },
});

const { t } = useI18n();
</script>

<template>
  <a
    v-if="botao.endereco"
    :href="botao.endereco"
    target="_blank"
    rel="noopener noreferrer"
    :class="classe"
    class="hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
    :data-tipo-do-botao="botao.tipo"
  >
    <Icon :icon="botao.icone" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">{{ botao.texto }}</span>
    <span class="sr-only">{{
      t('CONVERSA_CANAL.MODELO.ABRE_EM_OUTRA_ABA')
    }}</span>
  </a>
  <div
    v-else
    :class="classe"
    :title="t('CONVERSA_CANAL.MODELO.SO_NO_CELULAR')"
    :data-tipo-do-botao="botao.tipo"
  >
    <Icon :icon="botao.icone" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">{{ botao.texto }}</span>
  </div>
</template>
