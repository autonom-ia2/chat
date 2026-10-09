<script setup>
// Campo-armadilha (J2-A4): fora da tela, fora da tabulação e escondido do leitor de tela. Gente não preenche;
// robô costuma preencher, e o servidor recusa sem dizer o motivo. Rótulo fixo, fora das traduções, de propósito.
const model = defineModel({ type: String, default: '' });
const honeypotLabel = 'Company';
</script>

<template>
  <div
    class="absolute -left-[9999px] top-auto h-px w-px overflow-hidden"
    aria-hidden="true"
  >
    <label for="booking-company">{{ honeypotLabel }}</label>
    <input
      id="booking-company"
      v-model="model"
      type="text"
      name="company"
      tabindex="-1"
      autocomplete="off"
    />
  </div>
</template>
