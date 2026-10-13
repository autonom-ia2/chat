<script setup>
import { nextTick, ref } from 'vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import AgenteAvatar from '../AgenteAvatar.vue';

// #1366 (protótipo da Fase 2, rodada 2) — cartões grandes de escolha da jornada "Onde trabalha".
// Uma escolha (role=radio, um só item no Tab e setas que andam e marcam) ou várias (role=checkbox,
// cada cartão no Tab). Cartão desabilitado continua visível e anunciado, com o motivo escrito.
// opcoes: [{ valor, titulo, texto?, exemplo?, aviso?, motivo?, desabilitada?, icone?, inbox?, avatar? }]
// `inbox`: a caixa da store (ícone do canal); `avatar`: { nome, src } de um agente.
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: [String, Number, Array], default: null },
  multiplo: { type: Boolean, default: false },
  // Dois cartões lado a lado no computador (passo "Como vai trabalhar?").
  lado: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const botoes = ref([]);

const marcado = opcao =>
  props.multiplo
    ? (props.modelValue || []).includes(opcao.valor)
    : props.modelValue === opcao.valor;

const disponiveis = () => props.opcoes.filter(opcao => !opcao.desabilitada);

const escolher = opcao => {
  if (opcao.desabilitada) return;
  if (!props.multiplo) {
    if (opcao.valor !== props.modelValue)
      emit('update:modelValue', opcao.valor);
    return;
  }
  const atual = props.modelValue || [];
  emit(
    'update:modelValue',
    atual.includes(opcao.valor)
      ? atual.filter(valor => valor !== opcao.valor)
      : [...atual, opcao.valor]
  );
};

const noTab = opcao => {
  if (props.multiplo) return !opcao.desabilitada;
  const atual = props.opcoes.find(item => marcado(item) && !item.desabilitada);
  return (atual || disponiveis()[0])?.valor === opcao.valor;
};

const mover = async (evento, opcao, passo) => {
  if (props.multiplo) return;
  evento.preventDefault();
  const lista = disponiveis();
  const indice = lista.findIndex(item => item.valor === opcao.valor);
  const proxima = lista[(indice + passo + lista.length) % lista.length];
  escolher(proxima);
  await nextTick();
  botoes.value[props.opcoes.indexOf(proxima)]?.focus();
};
</script>

<template>
  <div
    :role="multiplo ? 'group' : 'radiogroup'"
    :aria-label="rotulo"
    class="grid grid-cols-1 gap-3"
    :class="lado ? 'md:grid-cols-2 md:gap-4' : ''"
  >
    <button
      v-for="opcao in opcoes"
      :key="opcao.valor"
      ref="botoes"
      type="button"
      :data-opcao="opcao.valor"
      :role="multiplo ? 'checkbox' : 'radio'"
      :aria-checked="marcado(opcao) ? 'true' : 'false'"
      :aria-disabled="opcao.desabilitada ? 'true' : undefined"
      :tabindex="noTab(opcao) ? '0' : '-1'"
      class="relative flex items-start w-full gap-4 text-start transition rounded-2xl ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      :class="[
        lado ? 'p-5 md:p-6 min-h-32' : 'p-4 min-h-16',
        marcado(opcao)
          ? 'ring-2 ring-n-blue-11 bg-n-blue-2 shadow-sm'
          : 'ring-1 ring-n-slate-6 bg-n-solid-1 shadow-sm',
        opcao.desabilitada
          ? 'cursor-not-allowed'
          : marcado(opcao)
            ? ''
            : 'hover:ring-n-slate-8 hover:shadow-md',
      ]"
      @click="escolher(opcao)"
      @keydown.down="mover($event, opcao, 1)"
      @keydown.right="mover($event, opcao, 1)"
      @keydown.up="mover($event, opcao, -1)"
      @keydown.left="mover($event, opcao, -1)"
    >
      <AgenteAvatar
        v-if="opcao.avatar"
        :nome="opcao.avatar.nome"
        :src="opcao.avatar.src || ''"
        tom="atendendo"
      />
      <span
        v-else-if="opcao.inbox"
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-alpha-2"
      >
        <ChannelIcon :inbox="opcao.inbox" use-brand-icon class="size-6" />
      </span>
      <span
        v-else-if="opcao.icone"
        aria-hidden="true"
        class="grid rounded-xl place-items-center shrink-0"
        :class="[
          lado ? 'size-14' : 'size-12',
          opcao.desabilitada
            ? 'bg-n-slate-3 text-n-slate-10'
            : 'bg-n-blue-3 text-n-blue-11',
        ]"
      >
        <span :class="opcao.icone" class="size-6" />
      </span>
      <span class="flex flex-col gap-1 pe-8 grow min-w-0">
        <span
          class="font-semibold"
          :class="[
            lado ? 'text-lg' : 'text-base',
            opcao.desabilitada ? 'text-n-slate-11' : 'text-n-slate-12',
          ]"
        >
          {{ opcao.titulo }}
        </span>
        <span v-if="opcao.texto" class="text-sm text-n-slate-11">
          {{ opcao.texto }}
        </span>
        <span v-if="opcao.exemplo" class="mt-1 text-sm italic text-n-slate-11">
          {{ opcao.exemplo }}
        </span>
        <span
          v-if="opcao.aviso"
          data-aviso
          class="flex items-start gap-2 px-3 py-2 mt-2 text-sm rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
        >
          <span
            class="i-lucide-info size-4 mt-0.5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ opcao.aviso }}
        </span>
        <span
          v-if="opcao.desabilitada && opcao.motivo"
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
            : 'ring-2 ring-inset ring-n-slate-7'
        "
      >
        <span v-if="marcado(opcao)" class="i-lucide-check size-4" />
      </span>
    </button>
  </div>
</template>
