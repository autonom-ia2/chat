<script setup>
import { computed } from 'vue';
import { larguraDaBarra } from 'dashboard/routes/dashboard/relacionamentos/trazer/larguraDaBarra';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';
import { TIPOS, colunasDoCartao, progresso } from '../regras';

// #3100 — o cartão fidelidade como o cliente o imagina: o cartãozinho de papel
// com as bolinhas carimbadas e o prêmio na última. Em pontos, uma barra com
// "320 de 500 pontos". O mesmo cartão aparece na prévia de quem monta, no
// painel da Fidelidade e na ficha (`compacto`). O desenho é só desenho
// (aria-hidden); a frase de cima diz o mesmo para o leitor de tela. No painel
// o cartão é o modelo da conta, não o de alguém (`modelo`): a frase diz
// "Cartão de 10 carimbos" em vez de quanto falta.
const props = defineProps({
  tipo: { type: String, default: TIPOS.CARIMBOS },
  meta: { type: Number, required: true },
  tem: { type: Number, default: 0 },
  premio: { type: String, default: '' },
  regra: { type: String, default: '' },
  compacto: { type: Boolean, default: false },
  modelo: { type: Boolean, default: false },
});

const { t, unidade } = useTextosDaFidelidade();

const conta = computed(() => progresso(props.tem, props.meta));
const ehCarimbo = computed(() => props.tipo !== TIPOS.PONTOS);
const COLUNAS = {
  2: 'grid-cols-2',
  3: 'grid-cols-3',
  4: 'grid-cols-4',
  5: 'grid-cols-5',
  6: 'grid-cols-6',
};
const colunas = computed(() => COLUNAS[colunasDoCartao(props.meta)]);
const bolinhas = computed(() =>
  Array.from({ length: props.meta || 0 }, (_, i) => ({
    i,
    cheia: i < conta.value.feitos,
    premio: i === props.meta - 1,
  }))
);
const barra = computed(() =>
  larguraDaBarra(props.meta ? (conta.value.feitos / props.meta) * 100 : 0)
);
const frase = computed(() => {
  if (props.modelo)
    return t(`${F}.CARTAO.MODELO`, { meta: unidade(props.meta, props.tipo) });
  if (conta.value.completo) return t(`${F}.CARTAO.COMPLETO`);
  return t(
    `${F}.CARTAO.FALTAM`,
    { quantos: unidade(conta.value.faltam, props.tipo) },
    conta.value.faltam
  );
});
</script>

<template>
  <div
    data-fidelidade="cartao"
    class="relative flex flex-col overflow-hidden border shadow-sm rounded-3xl border-n-weak bg-n-solid-1"
    :class="compacto ? 'gap-4 p-4' : 'gap-5 p-5 md:p-6'"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-10 -top-12 size-36 bg-n-teal-3 opacity-60"
    />
    <div class="relative flex items-start gap-3">
      <span
        class="flex items-center justify-center rounded-2xl shrink-0 bg-n-teal-9 text-white"
        :class="compacto ? 'size-10' : 'size-12'"
        aria-hidden="true"
      >
        <span class="i-lucide-gift" :class="compacto ? 'size-5' : 'size-6'" />
      </span>
      <div class="min-w-0">
        <p class="m-0 text-xs font-semibold text-n-teal-11">
          {{ t(`${F}.CARTAO.PREMIO`) }}
        </p>
        <p
          data-fidelidade="premio"
          class="m-0 font-semibold leading-snug text-n-slate-12 text-pretty"
          :class="compacto ? 'text-base' : 'text-lg md:text-xl'"
        >
          {{ premio || t(`${F}.VAZIO.EXEMPLO_PREMIO`) }}
        </p>
      </div>
    </div>

    <p
      class="relative m-0 text-sm font-medium"
      :class="conta.completo ? 'text-n-teal-11' : 'text-n-slate-11'"
    >
      <span v-if="!modelo" class="sr-only">
        {{
          t(`${F}.CARTAO.LEITOR`, {
            tem: conta.tem,
            meta,
            unidade: unidade(meta, tipo),
          })
        }}
      </span>
      {{ frase }}
    </p>

    <div
      v-if="ehCarimbo"
      aria-hidden="true"
      data-fidelidade="bolinhas"
      class="relative grid gap-2 sm:gap-3 justify-items-center"
      :class="[colunas, compacto ? 'max-w-xs' : '']"
    >
      <span
        v-for="bolinha in bolinhas"
        :key="bolinha.i"
        :data-cheia="bolinha.cheia ? '' : undefined"
        class="flex items-center justify-center w-full rounded-full aspect-square"
        :class="[
          bolinha.cheia
            ? 'bg-n-teal-9 text-white shadow-sm'
            : 'border-2 border-dashed border-n-slate-6 text-n-slate-9',
          compacto ? 'max-w-11' : 'max-w-16',
        ]"
      >
        <span
          v-if="bolinha.premio"
          class="i-lucide-gift"
          :class="compacto ? 'size-4' : 'size-5'"
        />
        <span
          v-else-if="bolinha.cheia"
          class="i-lucide-check"
          :class="compacto ? 'size-4' : 'size-5'"
        />
      </span>
    </div>

    <div v-else aria-hidden="true" data-fidelidade="barra" class="relative">
      <div class="flex h-3 overflow-hidden rounded-full bg-n-alpha-2">
        <span class="h-full rounded-full bg-n-teal-9" :class="barra" />
      </div>
      <p class="m-0 mt-2 text-sm tabular-nums text-n-slate-11">
        {{ t(`${F}.CARTAO.DE`, { tem: conta.tem, meta: unidade(meta, tipo) }) }}
      </p>
    </div>

    <p
      v-if="regra"
      data-fidelidade="regra"
      class="relative m-0 text-sm text-n-slate-11"
    >
      {{ regra }}
    </p>
  </div>
</template>
