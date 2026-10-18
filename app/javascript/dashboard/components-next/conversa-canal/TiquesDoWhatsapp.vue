<script setup>
// Tiques do WhatsApp (#1702), desenho nosso na forma do app: um tique (enviada), dois
// (entregue) e dois azuis (lida). A cor dos cinzas vem da hora ao lado (na foto, branco).
import { MESSAGE_STATUS } from '../message/constants';

defineProps({
  status: { type: String, required: true },
  rotulo: { type: String, default: '' },
});
</script>

<template>
  <svg
    v-if="status !== MESSAGE_STATUS.PROGRESS"
    viewBox="0 0 16 11"
    width="16"
    height="11"
    fill="none"
    stroke="currentColor"
    stroke-width="1.5"
    stroke-linecap="round"
    stroke-linejoin="round"
    role="img"
    :aria-label="rotulo"
    :class="status === MESSAGE_STATUS.READ ? 'text-[#53BDEB]' : ''"
    data-tiques-do-whatsapp
  >
    <path v-if="status === MESSAGE_STATUS.SENT" d="M3.5 5.8 6.3 8.6 12 2.4" />
    <template v-else>
      <path d="M1 5.8 3.8 8.6 9.5 2.4" />
      <path d="M7.4 8 8 8.6 13.7 2.4" />
    </template>
  </svg>
  <svg
    v-else
    viewBox="0 0 16 16"
    width="14"
    height="14"
    fill="none"
    stroke="currentColor"
    stroke-width="1.4"
    stroke-linecap="round"
    role="img"
    :aria-label="rotulo"
    data-tiques-do-whatsapp
  >
    <circle cx="8" cy="8" r="6.2" />
    <path d="M8 4.6V8l2.2 1.4" />
  </svg>
</template>
