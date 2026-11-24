<script setup>
import { computed, nextTick, ref } from 'vue';
import { useMediaQuery } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CartaoDeCarimbos from './CartaoDeCarimbos.vue';
import EscolhaEmCartoes from './EscolhaEmCartoes.vue';
import { F, useTextosDaFidelidade } from '../useTextosDaFidelidade';
import {
  METAS_DE_CARIMBO,
  TIPOS,
  VALIDADES,
  carimbosDaCompra,
  compraDeExemplo,
  errosDoPrograma,
  saldoDeExemplo,
  trocarTipo,
} from '../regras';

// #3100 — montar (ou mudar) o cartão fidelidade da conta, numa tela só: à
// esquerda as quatro perguntas (como junta, a cada quanto, quantos para o
// prêmio, qual prêmio) e até quando valem; à direita o cartão de um cliente
// de exemplo, mudando junto (no celular, compacto e depois do formulário: as
// perguntas vêm primeiro). O botão principal nunca fica apagado: tocado com algo faltando, cada
// campo diz o que falta (`tentou`), a faixa vermelha acima dos botões avisa e
// o foco vai ao primeiro campo errado. O programa entra e sai inteiro por
// `modelValue`; quem usa grava no servidor ao `salvar`.
const props = defineProps({
  modelValue: { type: Object, required: true },
  novo: { type: Boolean, default: true },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'salvar', 'cancelar']);

const { t, unidade, dinheiro, regra } = useTextosDaFidelidade();
const M = `${F}.MONTAR`;

const programa = computed(() => props.modelValue);
const ehCarimbo = computed(() => programa.value.tipo !== TIPOS.PONTOS);
const mudar = mudanca =>
  emit('update:modelValue', { ...programa.value, ...mudanca });

const tentou = ref(false);
const erros = computed(() =>
  tentou.value ? errosDoPrograma(programa.value) : []
);
const erroDe = campo => (erros.value.includes(campo) ? 'error' : 'info');
const invalido = campo => erros.value.includes(campo) || undefined;
const mensagem = (campo, dica = '') => {
  if (!erros.value.includes(campo)) return dica;
  if (campo === 'META' && !ehCarimbo.value) return t(`${M}.ERROS.META_PONTOS`);
  return t(`${M}.ERROS.${campo}`);
};

// O foco leva a tela até o campo (no celular ele pode estar fora da vista).
const formulario = ref(null);
const salvar = async () => {
  tentou.value = true;
  if (!errosDoPrograma(programa.value).length) {
    emit('salvar');
    return;
  }
  await nextTick();
  formulario.value
    ?.querySelector(':is(input, button)[aria-invalid="true"]')
    ?.focus();
};
const telaGrande = useMediaQuery('(min-width: 1024px)');

const tipos = computed(() => [
  {
    value: TIPOS.CARIMBOS,
    titulo: t(`${M}.TIPO_CARIMBOS`),
    dica: t(`${M}.TIPO_CARIMBOS_DICA`),
    icone: 'i-lucide-stamp',
  },
  {
    value: TIPOS.PONTOS,
    titulo: t(`${M}.TIPO_PONTOS`),
    dica: t(`${M}.TIPO_PONTOS_DICA`),
    icone: 'i-lucide-coins',
  },
]);
const GANHOS_DE_CARIMBO = [1, 2, 3];
const ganhos = computed(() =>
  GANHOS_DE_CARIMBO.map(n => ({ value: n, label: unidade(n) }))
);
const metas = computed(() =>
  METAS_DE_CARIMBO.map(n => ({ value: n, label: unidade(n) }))
);
const validades = computed(() =>
  VALIDADES.map(meses => ({
    value: meses,
    label:
      meses === null
        ? t(`${M}.VALIDADES.SEMPRE`)
        : t(`${M}.VALIDADES.MESES`, { count: meses }, meses),
  }))
);

// A prévia: um cliente que já tem quase tudo, e uma compra de exemplo que
// mostra que o troco não passa para a próxima (R$ 120 = 2 carimbos).
const exemploNoCartao = computed(() => saldoDeExemplo(programa.value));
const temRegra = computed(
  () => Number.isInteger(programa.value.a_cada) && programa.value.a_cada > 0
);
const resumo = computed(() => {
  const compra = compraDeExemplo(programa.value);
  return t(`${M}.RESUMO`, {
    exemplo: dinheiro(compra, programa.value.moeda),
    ganha: unidade(
      carimbosDaCompra(compra, programa.value),
      programa.value.tipo
    ),
  });
});
</script>

<template>
  <div data-fidelidade="montar" class="flex flex-col gap-6">
    <header class="flex flex-col gap-2">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight outline-none text-n-slate-12 md:text-3xl"
      >
        {{ novo ? t(`${M}.TITULO_NOVO`) : t(`${M}.TITULO_MUDAR`) }}
      </h1>
      <p class="m-0 text-base text-n-slate-11">{{ t(`${M}.APOIO`) }}</p>
    </header>

    <div class="flex flex-col gap-6 lg:grid lg:grid-cols-5 lg:items-start">
      <aside
        class="flex flex-col order-2 gap-3 lg:col-span-2 lg:sticky lg:top-6"
      >
        <p class="m-0 text-sm font-medium text-n-slate-11">
          {{ t(`${M}.PREVIA`) }}
        </p>
        <CartaoDeCarimbos
          :tipo="programa.tipo"
          :meta="Number.isInteger(programa.meta) ? programa.meta : 0"
          :tem="exemploNoCartao"
          :premio="programa.premio"
          :regra="temRegra ? regra(programa) : ''"
          :compacto="!telaGrande"
        />
        <p
          v-if="temRegra"
          data-fidelidade="resumo"
          class="px-4 py-3 m-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-12"
        >
          {{ resumo }}
        </p>
      </aside>

      <section
        ref="formulario"
        class="flex flex-col gap-6 p-5 border shadow-sm lg:order-1 lg:col-span-3 rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
      >
        <EscolhaEmCartoes
          :model-value="programa.tipo"
          :legenda="t(`${M}.TIPO`)"
          :opcoes="tipos"
          @update:model-value="
            tipo => emit('update:modelValue', trocarTipo(programa, tipo))
          "
        />

        <div class="grid gap-4 sm:grid-cols-2">
          <Input
            data-fidelidade="a-cada"
            type="number"
            min="1"
            inputmode="numeric"
            :model-value="programa.a_cada ?? ''"
            :label="t(`${M}.A_CADA`)"
            :message="mensagem('A_CADA')"
            :message-type="erroDe('A_CADA')"
            :aria-invalid="invalido('A_CADA')"
            wrap-message
            @update:model-value="
              valor => mudar({ a_cada: valor === '' ? null : valor })
            "
          />
          <div v-if="ehCarimbo" class="flex flex-col gap-1">
            <span class="mb-0.5 text-heading-3 text-n-slate-12">
              {{ t(`${M}.GANHA`) }}
            </span>
            <ChoiceSelect
              data-fidelidade="ganha"
              :model-value="programa.ganha"
              :aria-label="t(`${M}.GANHA`)"
              :options="ganhos"
              @update:model-value="ganha => mudar({ ganha })"
            />
          </div>
          <Input
            v-else
            data-fidelidade="ganha"
            type="number"
            min="1"
            inputmode="numeric"
            :model-value="programa.ganha ?? ''"
            :label="t(`${M}.GANHA_PONTOS`)"
            :message="mensagem('GANHA')"
            :message-type="erroDe('GANHA')"
            :aria-invalid="invalido('GANHA')"
            wrap-message
            @update:model-value="
              valor => mudar({ ganha: valor === '' ? null : valor })
            "
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div v-if="ehCarimbo" class="flex flex-col gap-1">
            <span class="mb-0.5 text-heading-3 text-n-slate-12">
              {{ t(`${M}.META`) }}
            </span>
            <ChoiceSelect
              data-fidelidade="meta"
              :model-value="programa.meta"
              :aria-label="t(`${M}.META`)"
              :options="metas"
              :invalid="erros.includes('META')"
              @update:model-value="meta => mudar({ meta })"
            />
            <p v-if="erros.includes('META')" class="m-0 text-sm text-n-ruby-11">
              {{ mensagem('META') }}
            </p>
          </div>
          <Input
            v-else
            data-fidelidade="meta"
            type="number"
            min="2"
            inputmode="numeric"
            :model-value="programa.meta ?? ''"
            :label="t(`${M}.META_PONTOS`)"
            :message="mensagem('META')"
            :message-type="erroDe('META')"
            :aria-invalid="invalido('META')"
            wrap-message
            @update:model-value="
              valor => mudar({ meta: valor === '' ? null : valor })
            "
          />
          <div class="flex flex-col gap-1">
            <span class="mb-0.5 text-heading-3 text-n-slate-12">
              {{ t(`${M}.VALIDADE`) }}
            </span>
            <ChoiceSelect
              data-fidelidade="validade"
              :model-value="programa.validade_meses"
              :aria-label="t(`${M}.VALIDADE`)"
              :options="validades"
              @update:model-value="validade_meses => mudar({ validade_meses })"
            />
          </div>
        </div>

        <Input
          data-fidelidade="premio"
          :model-value="programa.premio || ''"
          :label="t(`${M}.PREMIO`)"
          :placeholder="t(`${M}.PREMIO_EXEMPLO`)"
          maxlength="80"
          :message="mensagem('PREMIO')"
          :message-type="erroDe('PREMIO')"
          :aria-invalid="invalido('PREMIO')"
          wrap-message
          @update:model-value="premio => mudar({ premio })"
        />

        <p
          data-fidelidade="aviso"
          role="note"
          class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-blue-12"
        >
          <span
            class="i-lucide-info mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ novo ? t(`${M}.COMECA_DO_ZERO`) : t(`${M}.MUDAR_AVISO`) }}
        </p>

        <p
          v-if="erros.length"
          data-fidelidade="erro-geral"
          role="alert"
          class="flex items-start gap-2 px-4 py-3 m-0 text-sm font-medium rounded-xl bg-n-ruby-2 text-n-ruby-12"
        >
          <span
            class="i-lucide-circle-alert mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${M}.ERROS.TUDO`) }}
        </p>

        <div
          class="flex flex-col-reverse gap-3 pt-2 border-t sm:flex-row sm:justify-end border-n-weak"
        >
          <Button
            variant="faded"
            color="slate"
            size="lg"
            class="min-h-11"
            :label="t(`${M}.CANCELAR`)"
            @click="emit('cancelar')"
          />
          <Button
            data-fidelidade="salvar"
            class="min-h-11"
            size="lg"
            :is-loading="salvando"
            :disabled="salvando"
            :label="novo ? t(`${M}.SALVAR_NOVO`) : t(`${M}.SALVAR`)"
            @click="salvar"
          />
        </div>
      </section>
    </div>
  </div>
</template>
