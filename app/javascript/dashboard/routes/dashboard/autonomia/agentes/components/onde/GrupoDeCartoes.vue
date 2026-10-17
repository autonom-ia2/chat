<script setup>
import { useId } from 'vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import AgenteAvatar from '../AgenteAvatar.vue';

// #1366 (protótipo da Fase 2, rodada 2; real no #1433, tema 13) — cartões grandes de escolha de "Onde
// trabalha": hoje, os canais do agente da equipe. Várias escolhas (role=checkbox, cada cartão no Tab,
// Espaço ou Enter marca). O cartão bloqueado continua visível, no Tab e anunciado (aria-disabled),
// com o motivo escrito e ligado a ele (aria-describedby), para o leitor de tela dizer por quê.
// opcoes: [{ valor, titulo, texto?, motivo?, desabilitada?, inbox?, avatar? }] — `inbox`: a caixa da store (ícone);
// `avatar` ({ nome, src, tom? }, tema 14): a foto do agente, nos agentes que o ajudante pode ajudar.
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const base = `cartoes-${useId()}`;

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
</script>

<template>
  <div role="group" :aria-label="rotulo" class="grid grid-cols-1 gap-3">
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
      class="relative flex items-start w-full gap-4 p-4 shadow-sm text-start transition rounded-2xl ring-inset min-h-16 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      :class="[
        marcado(opcao)
          ? 'ring-2 ring-n-blue-11 bg-n-blue-2'
          : 'ring-1 ring-n-slate-6 bg-n-solid-1',
        opcao.desabilitada
          ? 'cursor-not-allowed'
          : marcado(opcao)
            ? ''
            : 'hover:ring-n-slate-8 hover:shadow-md',
      ]"
      @click="escolher(opcao)"
    >
      <span
        v-if="opcao.inbox"
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-alpha-2"
        :class="opcao.desabilitada ? 'opacity-60' : ''"
      >
        <ChannelIcon :inbox="opcao.inbox" use-brand-icon class="size-6" />
      </span>
      <AgenteAvatar
        v-else-if="opcao.avatar"
        :nome="opcao.avatar.nome"
        :src="opcao.avatar.src || ''"
        :tom="opcao.avatar.tom || 'neutro'"
        :class="opcao.desabilitada ? 'opacity-60' : ''"
      />
      <span class="flex flex-col gap-1 pe-8 grow min-w-0">
        <span
          class="text-base font-semibold"
          :class="opcao.desabilitada ? 'text-n-slate-11' : 'text-n-slate-12'"
        >
          {{ opcao.titulo }}
        </span>
        <span v-if="opcao.texto" class="text-sm text-n-slate-11">
          {{ opcao.texto }}
        </span>
        <span
          v-if="opcao.desabilitada && opcao.motivo"
          :id="idDoMotivo(opcao)"
          data-motivo
          class="flex items-start gap-2 mt-1 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-lock size-4 mt-0.5 shrink-0"
            aria-hidden="true"
          />
          {{ opcao.motivo }}
        </span>
      </span>
      <span
        aria-hidden="true"
        class="absolute grid rounded-full top-4 end-4 size-6 place-items-center"
        :class="
          marcado(opcao)
            ? 'bg-n-blue-11 text-white dark:text-n-slate-1'
            : opcao.desabilitada
              ? 'ring-2 ring-inset ring-n-slate-5'
              : 'ring-2 ring-inset ring-n-slate-7'
        "
      >
        <span v-if="marcado(opcao)" class="i-lucide-check size-4" />
      </span>
    </button>
  </div>
</template>
