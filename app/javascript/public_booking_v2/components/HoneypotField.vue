<script setup>
// Campo-armadilha (J2-A4): fora da tela, fora da tabulação e escondido do leitor de tela. Gente não preenche;
// robô costuma preencher, e o servidor recusa sem dizer o motivo. Nome e rótulo sem sentido para o autopreenchimento
// do navegador ou do gerenciador de senhas (um "company" seria preenchido sozinho no celular de gente de verdade).
// No JSON continua `company`. Rótulo fixo, fora das traduções, de propósito.
const model = defineModel({ type: String, default: '' });
const honeypotLabel = 'Ref X';
</script>

<template>
  <div
    class="absolute -left-[9999px] top-auto h-px w-px overflow-hidden"
    aria-hidden="true"
  >
    <label for="booking-hp-field">{{ honeypotLabel }}</label>
    <input
      id="booking-hp-field"
      v-model="model"
      type="text"
      name="hp_field_x"
      tabindex="-1"
      autocomplete="off"
      data-1p-ignore
      data-lpignore="true"
      data-form-type="other"
    />
  </div>
</template>
