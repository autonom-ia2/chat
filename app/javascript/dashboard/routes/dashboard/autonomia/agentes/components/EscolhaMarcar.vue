<script setup>
import { useId } from 'vue';

// #1433 — cartões de escolha múltipla no MESMO tamanho e estilo compacto do EscolhaRadio (decisão do Rodrigo de
// 15/10: a seção "Também recebe quando alguém passar em:" fica igual a "Onde atende"). Padrão WAI-ARIA de grupo de
// caixas de seleção: role=checkbox, cada cartão no Tab, Espaço ou Enter marca, alvo de 44 px. A opção bloqueada
// continua visível, no Tab e anunciada (aria-disabled), com o motivo escrito e ligado a ela (aria-describedby).
// opcoes: [{ valor, titulo, texto?, etiqueta?, motivo?, desabilitada? }]
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const base = `marcar-${useId()}`;

const marcado = opcao => props.modelValue.includes(opcao.valor);

const escolher = opcao => {
  if (opcao.desabilitada) return;
  emit(
    'update:modelValue',
    marcado(opcao)
      ? props.modelValue.filter(valor => valor !== opcao.valor)
      : [...props.modelValue, opcao.valor]
  );
};

const idDoMotivo = opcao => `${base}-${opcao.valor}`;

const classeDaOpcao = opcao => {
  if (marcado(opcao)) return 'ring-2 ring-n-blue-11 bg-n-blue-2';
  return opcao.desabilitada
    ? 'ring-n-slate-7 bg-n-solid-1'
    : 'ring-n-slate-7 bg-n-solid-1 hover:bg-n-slate-2';
};
</script>

<template>
  <div role="group" :aria-label="rotulo" class="flex flex-col gap-2">
    <button
      v-for="opcao in opcoes"
      :key="opcao.valor"
      type="button"
      role="checkbox"
      :data-opcao="opcao.valor"
      :aria-checked="marcado(opcao) ? 'true' : 'false'"
      :aria-disabled="opcao.desabilitada ? 'true' : undefined"
      :aria-describedby="
        opcao.desabilitada && opcao.motivo ? idDoMotivo(opcao) : undefined
      "
      class="flex items-start w-full gap-3 px-4 py-3 text-start transition rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      :class="[
        classeDaOpcao(opcao),
        opcao.desabilitada ? 'cursor-not-allowed opacity-70' : '',
      ]"
      @click="escolher(opcao)"
    >
      <span
        aria-hidden="true"
        class="grid mt-0.5 rounded place-items-center size-5 shrink-0 ring-2 ring-inset"
        :class="
          marcado(opcao) ? 'ring-n-blue-11 bg-n-blue-11' : 'ring-n-slate-8'
        "
      >
        <span
          v-if="marcado(opcao)"
          class="i-lucide-check size-3.5 text-white"
        />
      </span>
      <span class="flex flex-col gap-0.5 grow min-w-0">
        <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ opcao.titulo }}
          </span>
          <span
            v-if="opcao.etiqueta"
            data-etiqueta
            class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-full bg-n-slate-3 text-n-slate-12"
          >
            {{ opcao.etiqueta }}
          </span>
        </span>
        <span v-if="opcao.texto" class="text-sm text-n-slate-11">
          {{ opcao.texto }}
        </span>
        <span
          v-if="opcao.desabilitada && opcao.motivo"
          :id="idDoMotivo(opcao)"
          data-motivo
          class="flex items-start gap-1.5 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-lock size-4 mt-0.5 shrink-0"
            aria-hidden="true"
          />
          {{ opcao.motivo }}
        </span>
      </span>
    </button>
  </div>
</template>
