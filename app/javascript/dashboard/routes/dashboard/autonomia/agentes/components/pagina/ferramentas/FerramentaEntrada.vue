<script setup>
import { ref } from 'vue';

// #1301 — caixa de texto do assistente (44 px, anel slate 7, rubi quando inválida). "linhas" > 0
// vira textarea; "mono" é para endereço, nome técnico, corpo e chaves. Sem v-model no pai de
// objeto: emite o texto e quem usa monta o rascunho novo.
defineProps({
  id: { type: String, required: true },
  modelValue: { type: String, default: '' },
  linhas: { type: Number, default: 0 },
  mono: { type: Boolean, default: false },
  tipo: { type: String, default: 'text' },
  // Valor secreto: gerenciadores de senha não sugerem nem guardam (nem com Mostrar ligado).
  segredo: { type: Boolean, default: false },
  invalido: { type: Boolean, default: false },
  descricao: { type: String, default: undefined },
  placeholder: { type: String, default: undefined },
  inputmode: { type: String, default: undefined },
});

const emit = defineEmits(['update:modelValue', 'blur']);

const campo = ref(null);
const focar = () => campo.value?.focus();

defineExpose({ focar });
</script>

<template>
  <textarea
    v-if="linhas"
    :id="id"
    ref="campo"
    :value="modelValue"
    :rows="linhas"
    :spellcheck="mono ? 'false' : 'true'"
    :placeholder="placeholder"
    :inputmode="inputmode"
    :aria-invalid="invalido ? 'true' : undefined"
    :aria-describedby="descricao"
    class="w-full px-3 py-2 text-base rounded-xl bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12 resize-y break-words"
    :class="[
      mono ? 'font-mono' : '',
      invalido ? 'ring-n-ruby-9' : 'ring-n-slate-7',
    ]"
    @input="emit('update:modelValue', $event.target.value)"
    @blur="emit('blur')"
  />
  <input
    v-else
    :id="id"
    ref="campo"
    :value="modelValue"
    :type="tipo"
    :autocomplete="segredo || tipo === 'password' ? 'new-password' : 'off'"
    :data-1p-ignore="segredo || tipo === 'password' ? '' : undefined"
    :data-lpignore="segredo || tipo === 'password' ? 'true' : undefined"
    :spellcheck="mono ? 'false' : 'true'"
    :placeholder="placeholder"
    :inputmode="inputmode"
    :aria-invalid="invalido ? 'true' : undefined"
    :aria-describedby="descricao"
    class="w-full px-3 text-base rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset border-0 !mb-0 text-n-slate-12"
    :class="[
      mono ? 'font-mono' : '',
      invalido ? 'ring-n-ruby-9' : 'ring-n-slate-7',
    ]"
    @input="emit('update:modelValue', $event.target.value)"
    @blur="emit('blur')"
  />
</template>
