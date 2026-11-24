<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useTextosDaFidelidade } from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';
import { TIPOS, progresso } from 'dashboard/routes/dashboard/fidelidade/regras';
import { FA, MOTIVO_MAXIMO, QUANTOS_PARA_DAR } from './fidelidadeNaAutomacao';

// #3100 — o passo "Dar carimbos ou pontos" no "Alterar": quantos dar e, se
// quiser, o motivo (aparece no histórico da ficha: "Recebeu 2 carimbos:
// aniversário"). A faixa azul lembra que a compra já dá carimbos sozinha: este
// passo é para presente (aniversário, indicação, avaliação). O exemplo mostra
// o cartão de alguém antes e depois. Sem cartão fidelidade na conta, o passo
// diz para criar antes (`criarPrograma`). O passo entra e sai inteiro por
// `modelValue`, como os outros passos novos.
const props = defineProps({
  modelValue: { type: Object, required: true },
  programa: { type: Object, default: null },
});
const emit = defineEmits(['update:modelValue', 'criarPrograma']);

const { t, unidade, nomeDaUnidade } = useTextosDaFidelidade();
const D = `${FA}.DAR`;

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });
const ehPontos = computed(() => props.programa?.tipo === TIPOS.PONTOS);
const opcoes = computed(() =>
  QUANTOS_PARA_DAR.map(n => ({
    value: n,
    label: unidade(n, props.programa?.tipo),
  }))
);

// O exemplo: alguém a 3 do prêmio.
const exemplo = computed(() => {
  if (!props.programa) return null;
  const { meta, tipo } = props.programa;
  const antes = Math.max(0, meta - 3);
  const depois = antes + (props.modelValue.quantos || 0);
  const { completo } = progresso(depois, meta);
  return t(completo ? `${D}.EXEMPLO_COMPLETA` : `${D}.EXEMPLO`, {
    antes,
    depois: Math.min(depois, meta),
    meta: unidade(meta, tipo),
  });
});
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="dar_carimbos">
    <div
      v-if="!programa"
      data-fidelidade="sem-programa"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-amber-2 text-n-amber-12"
    >
      <p class="m-0 text-[0.9375rem] font-medium">
        {{ t(`${D}.SEM_PROGRAMA`) }}
      </p>
      <Button
        class="self-start min-h-11"
        color="amber"
        icon="i-lucide-gift"
        :label="t(`${D}.CRIAR`)"
        @click="emit('criarPrograma')"
      />
    </div>

    <template v-else>
      <p
        role="note"
        class="flex items-start gap-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-blue-12"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t(`${D}.AVISO_COMPRA`, { unidade: nomeDaUnidade(programa.tipo) }) }}
      </p>

      <Input
        v-if="ehPontos"
        data-fidelidade="quantos"
        type="number"
        min="1"
        inputmode="numeric"
        :model-value="modelValue.quantos ?? ''"
        :label="t(`${D}.QUANTOS`)"
        @update:model-value="
          valor => mudar({ quantos: valor === '' ? null : valor })
        "
      />
      <div v-else class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${D}.QUANTOS`) }}
        </span>
        <ChoiceSelect
          data-fidelidade="quantos"
          :model-value="modelValue.quantos"
          :aria-label="t(`${D}.QUANTOS`)"
          :options="opcoes"
          @update:model-value="quantos => mudar({ quantos })"
        />
      </div>

      <Input
        data-fidelidade="motivo"
        :model-value="modelValue.motivo || ''"
        :label="t(`${D}.MOTIVO`)"
        :placeholder="t(`${D}.MOTIVO_EXEMPLO`)"
        :maxlength="MOTIVO_MAXIMO"
        :message="t(`${D}.MOTIVO_DICA`)"
        wrap-message
        @update:model-value="motivo => mudar({ motivo })"
      />

      <p
        v-if="exemplo"
        data-fidelidade="exemplo"
        class="px-4 py-3 m-0 text-sm rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ exemplo }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${D}.REGRAS`, { unidade: nomeDaUnidade(programa.tipo) }) }}
      </p>
    </template>
  </div>
</template>
