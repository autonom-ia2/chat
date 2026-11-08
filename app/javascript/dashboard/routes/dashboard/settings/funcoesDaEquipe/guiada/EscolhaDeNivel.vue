<script setup>
import { computed, nextTick, ref, useId } from 'vue';

// Uma escolha de nível (#2308, especificação 14 › Acessibilidade): radiogroup com tabindex móvel. Só a opção
// escolhida entra no Tab; setas trocam a escolha (padrão WAI-ARIA radio group), Home e End vão às pontas. A opção
// que pede confirmação (`confirma`, o "Cuida de tudo" de Vendas) só recebe o foco pela seta: o diálogo abre só no
// clique, no Espaço ou no Enter, para quem percorre as opções não cair num aviso que não pediu (WCAG 3.2.2). A opção
// travada fica tracejada, com cadeado e o motivo, e as setas a pulam. O slot "dentro" aparece na escolhida, mas fica
// fora do grupo: o radiogroup é dono só dos botões (aria-owns), e os interruptores de dentro não contam como opção.
const props = defineProps({
  // { valor, titulo, dica?, trava?, confirma?, dentro? } — trava é o texto do motivo; dentro diz que a opção tem o
  // slot #dentro quando escolhida (sem ele, nada de linha vazia dentro do cartão).
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
  compacto: { type: Boolean, default: false },
});

const emit = defineEmits(['escolher']);
const modelo = defineModel({ type: String, required: true });

const botoes = ref([]);
const id = useId();
const idDa = indice => `${id}-opcao-${indice}`;
const donos = computed(() =>
  props.opcoes.map((_, indice) => idDa(indice)).join(' ')
);
const livres = computed(() => props.opcoes.filter(opcao => !opcao.trava));
const escolhidaLivre = computed(() =>
  livres.value.some(opcao => opcao.valor === modelo.value)
);
const noTab = opcao =>
  opcao.valor === modelo.value ||
  (!escolhidaLivre.value && opcao.valor === livres.value[0]?.valor);

const escolher = opcao => {
  if (opcao.trava) return;
  emit('escolher', opcao.valor);
  modelo.value = opcao.valor;
};

const PASSO = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 };
const alvoDaTecla = (tecla, indice) => {
  const lista = livres.value;
  if (tecla in PASSO)
    return lista[(indice + PASSO[tecla] + lista.length) % lista.length];
  if (tecla === 'Home') return lista[0];
  if (tecla === 'End') return lista[lista.length - 1];
  return null;
};

const mover = async (evento, opcao) => {
  const alvo = alvoDaTecla(evento.key, livres.value.indexOf(opcao));
  if (!alvo) return;
  evento.preventDefault();
  if (!alvo.confirma) escolher(alvo);
  await nextTick();
  botoes.value[props.opcoes.indexOf(alvo)]?.focus();
};
</script>

<template>
  <div class="flex gap-2" :class="compacto ? 'flex-wrap' : 'flex-col'">
    <div
      role="radiogroup"
      class="sr-only"
      :aria-label="rotulo"
      :aria-owns="donos"
    />
    <div
      v-for="(opcao, indice) in opcoes"
      :key="opcao.valor"
      class="border rounded-xl"
      :class="[
        compacto ? '' : 'w-full',
        opcao.trava
          ? 'border-dashed border-n-slate-8'
          : modelo === opcao.valor
            ? 'border-n-blue-8 bg-n-blue-2 ring-1 ring-n-blue-8'
            : 'border-n-weak bg-n-solid-1',
      ]"
    >
      <button
        :id="idDa(indice)"
        :ref="elemento => (botoes[indice] = elemento)"
        type="button"
        role="radio"
        :data-nivel="opcao.valor"
        :aria-checked="modelo === opcao.valor"
        :aria-disabled="Boolean(opcao.trava)"
        :tabindex="noTab(opcao) ? 0 : -1"
        class="flex items-start w-full gap-3 text-start min-h-11 rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="[
          compacto ? 'px-3 py-2.5' : 'px-4 py-3',
          opcao.trava ? 'cursor-not-allowed' : '',
        ]"
        @click="escolher(opcao)"
        @keydown="mover($event, opcao)"
      >
        <span
          v-if="opcao.trava"
          class="i-lucide-lock size-5 mt-px shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <span
          v-else
          aria-hidden="true"
          class="grid mt-px border-2 rounded-full place-items-center size-5 shrink-0"
          :class="
            modelo === opcao.valor ? 'border-n-brand' : 'border-n-slate-8'
          "
        >
          <span
            v-if="modelo === opcao.valor"
            class="rounded-full size-2.5 bg-n-brand"
          />
        </span>
        <span class="flex flex-col min-w-0 gap-0.5">
          <span
            class="font-medium"
            :class="opcao.trava ? 'text-n-slate-11' : 'text-n-slate-12'"
          >
            {{ opcao.titulo }}
          </span>
          <span v-if="opcao.dica" class="text-sm text-n-slate-11">
            {{ opcao.dica }}
          </span>
          <span v-if="opcao.trava" class="text-sm text-n-slate-11">
            {{ opcao.trava }}
          </span>
        </span>
      </button>
      <div
        v-if="opcao.dentro && $slots.dentro && modelo === opcao.valor"
        class="pb-2 ms-[3.25rem] me-4 border-t border-n-blue-6"
      >
        <slot name="dentro" :valor="opcao.valor" />
      </div>
    </div>
  </div>
</template>
