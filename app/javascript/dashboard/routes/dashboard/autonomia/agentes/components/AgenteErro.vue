<script setup>
import AgenteBotao from './AgenteBotao.vue';

// #1181 (protótipo T17) — o erro padrão do módulo: o que houve, o que continua igual (a garantia)
// e uma saída só. Âmbar para aviso (sem internet, sem canal); rubi para falha.
const props = defineProps({
  titulo: { type: String, required: true },
  garantia: { type: String, default: '' },
  acao: { type: String, default: '' },
  iconeAcao: { type: String, default: 'i-lucide-refresh-cw' },
  tom: {
    type: String,
    default: 'rubi',
    validator: v => ['rubi', 'ambar'].includes(v),
  },
  carregando: { type: Boolean, default: false },
});

const emit = defineEmits(['acao']);

const ambar = props.tom === 'ambar';
</script>

<template>
  <div
    role="alert"
    class="flex items-start gap-3 p-4 rounded-2xl ring-1 ring-inset"
    :class="ambar ? 'bg-n-amber-2 ring-n-amber-6' : 'bg-n-ruby-2 ring-n-ruby-6'"
  >
    <span
      aria-hidden="true"
      class="mt-0.5 size-5 shrink-0"
      :class="
        ambar
          ? 'i-lucide-triangle-alert text-n-amber-11'
          : 'i-lucide-circle-alert text-n-ruby-11'
      "
    />
    <div class="flex flex-col items-start gap-1 grow">
      <p class="m-0 text-sm font-semibold text-n-slate-12">{{ titulo }}</p>
      <p v-if="garantia" class="m-0 text-sm text-n-slate-11">{{ garantia }}</p>
      <AgenteBotao
        v-if="acao"
        variante="contorno"
        class="mt-2"
        :icone="iconeAcao"
        :carregando="carregando"
        @click="emit('acao')"
      >
        {{ acao }}
      </AgenteBotao>
    </div>
  </div>
</template>
