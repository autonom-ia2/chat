<script setup>
// Aviso das 24 horas no WhatsApp oficial (#1702): uma frase simples e o botão que
// abre a escolha de modelo de sempre (a mesma do botão de modelos da caixa de resposta).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';
import Button from 'next/button/Button.vue';
import { ABRIR_MODELOS_DO_WHATSAPP } from './pele';

const { t } = useI18n();
// O botão só aparece quando a caixa tem modelo para escolher (a mesma regra do botão
// de modelos da caixa de resposta).
const conversa = useMapGetter('getSelectedChat');
const modelosDaCaixa = useMapGetter('inboxes/getWhatsAppTemplates');
const temModelo = computed(
  () => (modelosDaCaixa.value(conversa.value?.inbox_id) || []).length > 0
);
const abrirModelos = () => emitter.emit(ABRIR_MODELOS_DO_WHATSAPP);
</script>

<template>
  <div
    role="status"
    class="flex flex-wrap items-center gap-3 ms-2 me-16 mt-2 px-4 py-3 rounded-lg bg-[#FFF3C4] dark:bg-[#3D3214] text-[#4A3B00] dark:text-[#F5E3A3] text-sm"
    data-aviso-janela-fechada
  >
    <Icon icon="i-ph-clock-countdown" class="size-5 flex-shrink-0" />
    <p class="flex-1 min-w-48">
      {{ t('CONVERSA_CANAL.JANELA_FECHADA.TEXTO') }}
    </p>
    <Button
      v-if="temModelo"
      sm
      color="teal"
      icon="i-ph-chat-text"
      :label="t('CONVERSA_CANAL.JANELA_FECHADA.ESCOLHER_MODELO')"
      @click="abrirModelos"
    />
  </div>
</template>
