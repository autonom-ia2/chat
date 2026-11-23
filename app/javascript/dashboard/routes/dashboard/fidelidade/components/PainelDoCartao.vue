<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDeEstado from 'dashboard/routes/dashboard/relacionamentos/components/comum/SeloDeEstado.vue';
import DialogoDaFicha from 'dashboard/routes/dashboard/relacionamentos/components/ficha/DialogoDaFicha.vue';
import CartaoDeCarimbos from './CartaoDeCarimbos.vue';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';

// #3100 — a aba "Cartão fidelidade" com o cartão já criado: o cartão da conta
// com a regra e a validade, três números dos últimos 30 dias e a ação
// principal, "Ver quem está perto do prêmio" (a lista de Relacionamentos já
// filtrada: é quem vale chamar agora). "Mudar as regras" e "Pausar o cartão"
// (com confirmação) só para quem pode (`podeMudar`, fidelidade_manage).
// Pausado, a faixa âmbar diz que as compras não estão dando carimbos e traz
// "Ligar o cartão de novo"; quem não pode lê a quem pedir. O cartão é o modelo
// da conta, sem saldo de ninguém. No celular os números vêm antes do cartão:
// a ação principal fica na primeira tela. `resumo` nulo é carregando.
const props = defineProps({
  programa: { type: Object, required: true },
  resumo: { type: Object, default: null },
  podeMudar: { type: Boolean, default: false },
});
const emit = defineEmits(['mudar', 'verPerto', 'pausar', 'ligar']);
const dialogoPausar = ref(null);
const pausar = () => {
  dialogoPausar.value?.close();
  emit('pausar');
};

const { t, nomeDaUnidade, regra } = useTextosDaFidelidade();
const P = `${F}.PAINEL`;

const validade = computed(() =>
  props.programa.validade_meses
    ? t(
        `${P}.VALIDADE`,
        {
          unidade: nomeDaUnidade(props.programa.tipo),
          count: props.programa.validade_meses,
        },
        props.programa.validade_meses
      )
    : t(`${P}.VALIDADE_SEMPRE`, {
        unidade: nomeDaUnidade(props.programa.tipo),
      })
);
const numeros = computed(() =>
  props.resumo
    ? [
        {
          id: 'com-saldo',
          valor: props.resumo.com_saldo,
          rotulo: t(`${P}.COM_SALDO`, {}, props.resumo.com_saldo),
        },
        {
          id: 'perto',
          valor: props.resumo.perto,
          rotulo: t(`${P}.PERTO`, {}, props.resumo.perto),
          destaque: props.resumo.perto > 0,
        },
        {
          id: 'premios',
          valor: props.resumo.premios_30d,
          rotulo: t(`${P}.PREMIOS`, {}, props.resumo.premios_30d),
        },
      ]
    : []
);
const passos = computed(() => [
  t(`${P}.PASSO_1`),
  t(`${P}.PASSO_2`, { unidade: nomeDaUnidade(props.programa.tipo) }),
  t(`${P}.PASSO_3`),
]);
const ninguem = computed(() => props.resumo && !props.resumo.com_saldo);
</script>

<template>
  <div data-fidelidade="painel" class="flex flex-col gap-6">
    <div
      v-if="!programa.ligado"
      data-fidelidade="pausado"
      role="status"
      class="flex flex-col gap-3 px-4 py-3 text-sm rounded-xl bg-n-amber-3 text-n-amber-12 sm:flex-row sm:items-center sm:justify-between"
    >
      <p class="flex items-start gap-2 m-0">
        <span
          class="i-lucide-pause-circle mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        <span>
          {{
            t(`${P}.PAUSADO_AVISO`, { unidade: nomeDaUnidade(programa.tipo) })
          }}
          <template v-if="!podeMudar">{{ t(`${P}.PECA_PARA_LIGAR`) }}</template>
        </span>
      </p>
      <Button
        v-if="podeMudar"
        data-fidelidade="ligar"
        color="amber"
        icon="i-lucide-play"
        class="w-full sm:w-auto min-h-11 shrink-0"
        :label="t(`${P}.LIGAR`)"
        @click="emit('ligar')"
      />
    </div>

    <div class="flex flex-col gap-6 lg:grid lg:grid-cols-5 lg:items-start">
      <section class="flex flex-col gap-3 lg:col-span-2">
        <div class="flex items-center justify-between gap-3">
          <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t(`${P}.SEU_CARTAO`) }}
          </h2>
          <SeloDeEstado :tom="programa.ligado ? 'verde' : 'ambar'">
            {{ programa.ligado ? t(`${P}.LIGADO`) : t(`${P}.DESLIGADO`) }}
          </SeloDeEstado>
        </div>
        <CartaoDeCarimbos
          :tipo="programa.tipo"
          :meta="programa.meta"
          :premio="programa.premio"
          :regra="regra(programa)"
          modelo
        />
        <p class="flex items-center gap-2 m-0 text-sm text-n-slate-11">
          <span
            class="i-lucide-calendar-clock size-4 shrink-0"
            aria-hidden="true"
          />
          {{ validade }}
        </p>
        <div v-if="podeMudar" class="flex flex-wrap gap-2">
          <Button
            data-fidelidade="mudar"
            variant="faded"
            color="slate"
            icon="i-lucide-pencil"
            class="min-h-11"
            :label="t(`${P}.MUDAR`)"
            @click="emit('mudar')"
          />
          <Button
            v-if="programa.ligado"
            data-fidelidade="pausar"
            variant="ghost"
            color="slate"
            icon="i-lucide-pause"
            class="min-h-11"
            :label="t(`${P}.PAUSAR`)"
            @click="dialogoPausar?.open()"
          />
        </div>
      </section>

      <section
        class="flex flex-col order-first gap-5 p-5 border shadow-sm lg:order-none lg:col-span-3 rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
      >
        <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ t(`${P}.NUMEROS`) }}
        </h2>
        <div
          v-if="!resumo"
          data-fidelidade="carregando"
          class="grid gap-3 sm:grid-cols-3"
          aria-busy="true"
        >
          <span
            v-for="n in 3"
            :key="n"
            class="h-24 rounded-2xl bg-n-slate-4 animate-pulse"
          />
        </div>
        <dl v-else class="grid gap-3 m-0 sm:grid-cols-3">
          <div
            v-for="numero in numeros"
            :key="numero.id"
            :data-fidelidade="`numero-${numero.id}`"
            class="flex flex-col gap-1 p-4 rounded-2xl"
            :class="numero.destaque ? 'bg-n-teal-2' : 'bg-n-alpha-1'"
          >
            <dt class="order-2 text-sm text-n-slate-11">{{ numero.rotulo }}</dt>
            <dd
              class="order-1 m-0 text-3xl font-bold leading-none tracking-tight tabular-nums"
              :class="numero.destaque ? 'text-n-teal-11' : 'text-n-slate-12'"
            >
              {{ numero.valor }}
            </dd>
          </div>
        </dl>
        <p
          v-if="ninguem"
          data-fidelidade="ninguem"
          class="m-0 text-base text-n-slate-11"
        >
          {{ t(`${P}.NINGUEM`, { unidade: nomeDaUnidade(programa.tipo) }) }}
        </p>
        <Button
          v-else-if="resumo"
          data-fidelidade="ver-perto"
          size="lg"
          icon="i-lucide-users"
          class="self-start min-h-11"
          :label="t(`${P}.VER_PERTO`)"
          @click="emit('verPerto')"
        />

        <div class="pt-5 border-t border-n-weak">
          <h3 class="m-0 mb-3 text-base font-semibold text-n-slate-12">
            {{ t(`${P}.COMO_FUNCIONA`) }}
          </h3>
          <ol class="flex flex-col gap-3 p-0 m-0 list-none">
            <li
              v-for="(passo, i) in passos"
              :key="i"
              class="flex items-start gap-3 text-[0.9375rem] text-n-slate-12"
            >
              <span
                class="flex items-center justify-center text-sm font-semibold rounded-full size-7 shrink-0 bg-n-alpha-2 text-n-slate-11 tabular-nums"
                aria-hidden="true"
              >
                {{ i + 1 }}
              </span>
              <span class="pt-0.5">{{ passo }}</span>
            </li>
          </ol>
        </div>
      </section>
    </div>

    <DialogoDaFicha
      v-if="podeMudar"
      ref="dialogoPausar"
      :titulo="t(`${P}.PAUSAR_TITULO`)"
      :texto="t(`${P}.PAUSAR_TEXTO`, { unidade: nomeDaUnidade(programa.tipo) })"
      :confirmar="t(`${P}.PAUSAR`)"
      :cancelar="t(`${P}.CANCELAR`)"
      marca-confirmar="confirmar-pausar"
      @confirm="pausar"
    />
  </div>
</template>
