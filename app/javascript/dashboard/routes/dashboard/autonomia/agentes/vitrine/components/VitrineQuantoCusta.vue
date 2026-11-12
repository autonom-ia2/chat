<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePremium } from '../usePremium';

// #2858 F7 — o quadro "Quanto custa" do detalhe Premium, no lugar do "Experimente" (cada consulta é paga). Responde, em
// ordem, o que um leigo pergunta: quantas grátis ainda tenho, quanto pago depois, o que conta e o que não conta, e
// quando as grátis voltam. Os números vêm do servidor; as regras são as da cobrança (Premium::Cobranca).
const props = defineProps({
  premium: { type: Object, required: true },
});

const NS = 'AGENTS.VITRINE.PREMIUM';
const { t } = useI18n();
const { gratis, restantes, estado, tom, marcas, faixa, preco } = usePremium(
  toRef(props, 'premium')
);

const acabaram = computed(() => estado.value === 'ACABARAM');

const regras = computed(() => [
  { chave: 'SEM_RESULTADO', icone: 'i-lucide-search-x' },
  // Só no card que recebe CPF ou CNPJ (`confere_documento`, do servidor): a placa e o endereço não têm documento.
  ...(props.premium.confere_documento
    ? [{ chave: 'NUMERO_ERRADO', icone: 'i-lucide-circle-slash' }]
    : []),
  { chave: 'MESMO_DIA', icone: 'i-lucide-repeat' },
  // A faixa de preço só existe quando o card tem perguntas de valores diferentes.
  ...(faixa.value?.min ? [{ chave: 'FAIXA', icone: 'i-lucide-tags' }] : []),
  { chave: 'FATURA', icone: 'i-lucide-receipt' },
]);
</script>

<template>
  <section
    data-vitrine-detalhe-premium
    :data-vitrine-estado="estado"
    aria-labelledby="vitrine-quanto-custa"
    class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-iris-6"
  >
    <h3
      id="vitrine-quanto-custa"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ t(`${NS}.TITULO`) }}
    </h3>

    <div class="flex flex-col gap-2">
      <p
        v-if="acabaram"
        data-vitrine-restantes
        class="m-0 text-xl font-bold leading-tight text-n-slate-12"
      >
        {{ t(`${NS}.ACABARAM`) }}
      </p>
      <p
        v-else
        data-vitrine-restantes
        class="flex flex-wrap items-baseline m-0 gap-x-2"
      >
        <span
          class="text-4xl font-bold leading-none tabular-nums"
          :class="tom.texto"
        >
          {{ restantes }}
        </span>
        {{ ' ' }}
        <span class="text-base text-n-slate-12">
          {{ t(`${NS}.CONTADOR.${estado}`, { gratis }) }}
        </span>
      </p>
      <span class="flex gap-1" aria-hidden="true">
        <span
          v-for="(sobra, indice) in marcas"
          :key="indice"
          class="flex-1 h-2 rounded-full"
          :class="sobra ? tom.marca : 'bg-n-slate-6'"
        />
      </span>
      <p
        data-vitrine-voltam
        class="flex items-center gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span class="i-lucide-refresh-cw size-4 shrink-0" aria-hidden="true" />
        {{ t(`${NS}.VOLTAM`, { gratis }) }}
      </p>
    </div>

    <p
      data-vitrine-preco
      class="flex flex-wrap items-baseline justify-between px-4 py-3 m-0 gap-x-3 gap-y-1 rounded-xl bg-n-iris-2 ring-1 ring-inset ring-n-iris-4"
    >
      <span class="text-sm text-n-slate-11">
        {{ t(acabaram ? `${NS}.PRECO_AGORA` : `${NS}.PRECO_DEPOIS`) }}
      </span>
      <span class="text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.POR_CONSULTA`, { preco }) }}
      </span>
    </p>

    <ul class="flex flex-col gap-2.5 p-0 m-0 list-none" data-vitrine-regras>
      <li
        v-for="regra in regras"
        :key="regra.chave"
        class="flex items-start gap-2.5 text-sm text-n-slate-12"
      >
        <span
          :class="regra.icone"
          class="size-4 mt-0.5 shrink-0 text-n-iris-11"
          aria-hidden="true"
        />
        {{ t(`${NS}.REGRAS.${regra.chave}`) }}
      </li>
    </ul>
  </section>
</template>
