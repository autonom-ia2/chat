<script setup>
// "Visto" embaixo da última mensagem nossa que o cliente leu (#2079). O Instagram não
// manda "entregue", e o painel não guarda a hora da leitura: fica só "Visto".
import { useI18n } from 'vue-i18n';
import { ROTULO } from './visualInstagram';

const { t } = useI18n();
</script>

<template>
  <li class="flex justify-end list-none -mt-1 mb-2">
    <span :class="ROTULO">{{ t('CONVERSA_CANAL.INSTAGRAM.VISTO') }}</span>
  </li>
</template>
