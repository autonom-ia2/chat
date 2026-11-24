<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';
import {
  carimbosDaCompra,
  compraDeExemplo,
  progresso,
  saldoDeExemplo,
} from '../regras';

// #3100 — logo depois de criar o cartão: diz que já está valendo e oferece os
// dois avisos prontos pelo WhatsApp (saldo depois da compra; cartão completo).
// Cada aviso abre a automação pronta e desligada em outra aba (`usar` com
// 'saldo' ou 'meta'), como as receitas da Automação livre; a pessoa confere e
// liga por lá. O aviso aberto troca o botão por "Pronto: o aviso abriu em
// outra aba", e o outro continua à mão. "Agora não" volta para o painel
// (`depois`); com algum aviso aberto, ele vira "Ver meu cartão". As mensagens
// de exemplo saem do programa criado (carimbos ou pontos, a meta e o quanto a
// compra dá), com o mesmo cliente de exemplo da tela de montar.
const props = defineProps({
  programa: { type: Object, required: true },
  nomeDeExemplo: { type: String, default: '' },
});
const emit = defineEmits(['usar', 'depois']);

const { t, unidade, nomeDaUnidade } = useTextosDaFidelidade();
const abertos = ref([]);
const usar = id => {
  abertos.value = [...abertos.value, id];
  emit('usar', id);
};
const P = `${F}.PRONTO`;
const AVISOS = [
  // O aviso do saldo é o que mais traz o cliente de volta: é o botão forte.
  { id: 'saldo', icone: 'i-lucide-receipt', variante: 'solid' },
  { id: 'meta', icone: 'i-lucide-party-popper', variante: 'faded' },
];
const valoresDoExemplo = computed(() => {
  const { tipo, meta } = props.programa;
  const tem = saldoDeExemplo(props.programa);
  return {
    nome: props.nomeDeExemplo || t(`${P}.NOME_DE_EXEMPLO`),
    ganhou: unidade(
      carimbosDaCompra(compraDeExemplo(props.programa), props.programa),
      tipo
    ),
    tem,
    meta: unidade(meta, tipo),
    faltam: unidade(progresso(tem, meta).faltam, tipo),
  };
});
</script>

<template>
  <div data-fidelidade="pronto" class="flex flex-col max-w-4xl gap-8 mx-auto">
    <header class="flex flex-col items-center gap-3 text-center">
      <span
        class="flex items-center justify-center text-white rounded-full shadow-lg size-16 bg-n-teal-9"
        aria-hidden="true"
      >
        <span class="i-lucide-check size-8" />
      </span>
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12 md:text-3xl text-balance"
      >
        {{ t(`${P}.TITULO`) }}
      </h1>
      <p class="max-w-xl m-0 text-base text-n-slate-11 text-pretty">
        {{ t(`${P}.APOIO`, { unidade: nomeDaUnidade(programa.tipo) }) }}
      </p>
    </header>

    <section class="flex flex-col gap-4">
      <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
        {{ t(`${P}.PERGUNTA`) }}
      </h2>
      <div class="grid gap-4 md:grid-cols-2">
        <article
          v-for="aviso in AVISOS"
          :key="aviso.id"
          :data-fidelidade="`aviso-${aviso.id}`"
          class="flex flex-col gap-4 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h3
            class="flex items-start gap-2 m-0 text-base font-semibold text-n-slate-12"
          >
            <span
              :class="aviso.icone"
              class="mt-0.5 size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            {{ t(`${P}.${aviso.id.toUpperCase()}_TITULO`) }}
          </h3>
          <figure
            class="flex flex-col flex-1 gap-2 p-3 m-0 rounded-2xl bg-n-alpha-1"
          >
            <figcaption class="text-xs font-medium text-n-slate-11">
              {{ t(`${P}.COMO_CHEGA`) }}
            </figcaption>
            <p
              class="self-start max-w-sm px-3 py-2 m-0 text-[0.9375rem] shadow-sm rounded-2xl rounded-ss-sm bg-n-teal-3 text-n-slate-12"
            >
              {{
                t(`${P}.${aviso.id.toUpperCase()}_EXEMPLO`, valoresDoExemplo)
              }}
            </p>
          </figure>
          <p
            v-if="abertos.includes(aviso.id)"
            :data-fidelidade="`aviso-aberto-${aviso.id}`"
            role="status"
            class="flex items-start gap-2 px-4 py-3 m-0 text-sm font-medium rounded-xl bg-n-teal-2 text-n-teal-12"
          >
            <span
              class="i-lucide-check mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ t(`${P}.ABERTO`) }}
          </p>
          <Button
            v-else
            class="w-full min-h-11"
            :variant="aviso.variante"
            :label="t(`${P}.USAR_${aviso.id.toUpperCase()}`)"
            @click="usar(aviso.id)"
          />
        </article>
      </div>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${P}.DICA`) }}</p>
    </section>

    <div class="flex justify-center">
      <Button
        variant="ghost"
        color="slate"
        class="min-h-11"
        :label="abertos.length ? t(`${P}.VER_CARTAO`) : t(`${P}.AGORA_NAO`)"
        @click="emit('depois')"
      />
    </div>
  </div>
</template>
