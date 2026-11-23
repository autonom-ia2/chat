<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDeEstado from 'dashboard/routes/dashboard/relacionamentos/components/comum/SeloDeEstado.vue';
import { SEPARADOR } from 'dashboard/routes/dashboard/relacionamentos/components/comum/ponto';
import { F, useTextosDaFidelidade } from '../../useTextosDaFidelidade';
import { exemploDeCodigo, taxaDeUso } from '../../regras';

// #3100 — um cupom no relatório: o nome (só a conta vê), o que ele dá, quanto
// tempo vale e o jeito do código; embaixo, quantos foram mandados, quantos
// usaram e quanto venderam. Quem não vê valores de venda (sales_value_view)
// recebe `vendas` nulo: o número vira um traço e o rótulo diz por quê. Cupom
// valendo e ainda não mandado traz "Mandar este cupom", que abre a automação
// pronta e desligada (como o "Usar o aviso" do ProgramaPronto). Quem pode
// (`podeMudar`, fidelidade_manage) pausa o cupom ou liga de novo no topo.
const props = defineProps({
  cupom: { type: Object, required: true },
  podeMudar: { type: Boolean, default: false },
});
const emit = defineEmits(['mandar', 'pausar', 'ligar']);

const { t, oferta, dinheiro } = useTextosDaFidelidade();
const C = `${F}.CUPONS`;

const taxa = computed(() => taxaDeUso(props.cupom));
const vendeu = computed(() => {
  const vendas = props.cupom.vendas;
  if (!vendas) return null;
  if (!vendas.length) return dinheiro(0, props.cupom.moeda);
  return vendas
    .map(({ total, moeda }) => dinheiro(total, moeda))
    .join(SEPARADOR);
});
const mandado = computed(() => props.cupom.mandados > 0);
const detalhe = computed(
  () =>
    `${oferta(props.cupom.oferta, props.cupom.moeda)}${SEPARADOR}${t(
      `${C}.VALE`,
      { count: props.cupom.validade_dias },
      props.cupom.validade_dias
    )}`
);
</script>

<template>
  <article
    :data-fidelidade="`cupom-${cupom.id}`"
    class="flex flex-col gap-4 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
  >
    <header class="flex items-start justify-between gap-3">
      <div class="flex items-start min-w-0 gap-3">
        <span
          class="flex items-center justify-center rounded-xl size-10 shrink-0 bg-n-amber-3 text-n-amber-11"
          aria-hidden="true"
        >
          <span class="i-lucide-ticket-percent size-5" />
        </span>
        <div class="min-w-0">
          <h3 class="m-0 text-base font-semibold truncate text-n-slate-12">
            {{ cupom.nome }}
          </h3>
          <p class="m-0 mt-0.5 text-sm text-n-slate-11">{{ detalhe }}</p>
        </div>
      </div>
      <div class="flex flex-col items-end gap-1 shrink-0">
        <SeloDeEstado :tom="cupom.ligado ? 'verde' : 'neutro'">
          {{ cupom.ligado ? t(`${C}.VALENDO`) : t(`${C}.PAUSADO`) }}
        </SeloDeEstado>
        <Button
          v-if="podeMudar"
          :data-fidelidade="cupom.ligado ? 'pausar-cupom' : 'ligar-cupom'"
          variant="ghost"
          color="slate"
          size="sm"
          class="min-h-11"
          :icon="cupom.ligado ? 'i-lucide-pause' : 'i-lucide-play'"
          :label="cupom.ligado ? t(`${C}.PAUSAR`) : t(`${C}.LIGAR`)"
          @click="cupom.ligado ? emit('pausar') : emit('ligar')"
        />
      </div>
    </header>

    <p class="flex flex-wrap items-center gap-2 m-0 text-sm text-n-slate-11">
      {{ t(`${C}.CODIGO_PARECE`) }}
      <code
        class="px-2 py-0.5 font-mono text-sm font-semibold tracking-wider rounded-md bg-n-alpha-2 text-n-slate-12"
      >
        {{ exemploDeCodigo(cupom.prefixo) }}
      </code>
    </p>

    <dl v-if="mandado" class="grid grid-cols-2 gap-2 m-0 sm:grid-cols-3">
      <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-alpha-1">
        <dt class="order-2 text-xs text-n-slate-11">
          {{ t(`${C}.MANDADOS`) }}
        </dt>
        <dd class="order-1 m-0 text-xl font-bold tabular-nums text-n-slate-12">
          {{ cupom.mandados }}
        </dd>
      </div>
      <div class="flex flex-col gap-0.5 p-3 rounded-xl bg-n-alpha-1">
        <dt class="order-2 text-xs text-n-slate-11">
          {{ t(`${C}.USADOS`, { taxa }) }}
        </dt>
        <dd class="order-1 m-0 text-xl font-bold tabular-nums text-n-slate-12">
          {{ cupom.usados }}
        </dd>
      </div>
      <div
        data-fidelidade="vendeu"
        class="flex flex-col col-span-2 gap-0.5 p-3 rounded-xl sm:col-span-1"
        :class="vendeu ? 'bg-n-teal-2' : 'bg-n-alpha-1'"
      >
        <dt class="order-2 text-xs text-n-slate-11">
          {{ vendeu ? t(`${C}.VENDERAM`) : t(`${C}.VENDERAM_SEM_ACESSO`) }}
        </dt>
        <dd
          v-if="vendeu"
          class="order-1 m-0 text-xl font-bold break-words tabular-nums text-n-teal-11"
        >
          {{ vendeu }}
        </dd>
        <dd
          v-else
          class="order-1 m-0 text-xl font-bold text-n-slate-11"
          aria-hidden="true"
        >
          —
        </dd>
      </div>
    </dl>
    <div
      v-else-if="cupom.ligado"
      data-fidelidade="nao-mandado"
      class="flex flex-col gap-3 px-4 py-3 rounded-xl bg-n-alpha-1 sm:flex-row sm:items-center sm:justify-between"
    >
      <p class="flex items-start gap-2 m-0 text-sm text-n-slate-11">
        <span class="i-lucide-send mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t(`${C}.NINGUEM`) }}
      </p>
      <Button
        v-if="podeMudar"
        data-fidelidade="mandar-cupom"
        icon="i-lucide-send"
        class="w-full sm:w-auto min-h-11 shrink-0"
        :label="t(`${C}.MANDAR`)"
        @click="emit('mandar')"
      />
    </div>
  </article>
</template>
