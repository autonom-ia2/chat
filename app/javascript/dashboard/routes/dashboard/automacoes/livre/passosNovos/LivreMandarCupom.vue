<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreTexto from '../components/LivreTexto.vue';
import LivreModelo from '../components/LivreModelo.vue';
import { useTextosDaFidelidade } from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';
import {
  exemploDeCodigo,
  textoDeExemplo,
} from 'dashboard/routes/dashboard/fidelidade/regras';
import { FA, comValoresDoCupom, faltaOCodigo } from './fidelidadeNaAutomacao';

// #3100 — o passo "Mandar cupom" no "Alterar": qual cupom e a mensagem. O
// texto é a caixa de sempre da Automação livre (LivreTexto), com os dados do
// cupom no "Pôr um dado" (código, o que dá, até quando vale) e o saldo do
// cartão (a dica embaixo da caixa diz que esses dados entram sozinhos). Cada
// cliente recebe um código só dele; quem já recebeu este cupom recebe o mesmo
// código de novo. Sem o código no texto, a faixa âmbar avisa.
// A prévia mostra a mensagem com um código de exemplo. Sem cupom criado, o
// passo diz para criar antes (`criarCupom`). Com a janela de 24 h fechada, vai
// o modelo aprovado escolhido (as variáveis dele também aceitam o código), ou
// nada, como no passo mensagem. Os dados do cupom só entram nas caixas daqui.
// O bloco do modelo fala sem "janela" nem "Meta" (`textos` do LivreModelo):
// "Se o cliente não falou com você nas últimas 24 horas…".
const props = defineProps({
  modelValue: { type: Object, required: true },
  cupons: { type: Array, default: () => [] },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  agora: { type: Number, required: true },
});
const emit = defineEmits(['update:modelValue', 'criarCupom']);

const { t, oferta, data } = useTextosDaFidelidade();
const C = `${FA}.CUPOM`;
const SEGUNDOS_POR_DIA = 86400;
const JANELA = `${C}.JANELA`;
const TEXTOS_DA_JANELA = {
  DICA: `${JANELA}.DICA`,
  NENHUM: `${JANELA}.NENHUM`,
  SEM_MODELOS: `${JANELA}.SEM_MODELOS`,
  SUMIU: `${JANELA}.SUMIU`,
};

const mudar = mudanca =>
  emit('update:modelValue', { ...props.modelValue, ...mudanca });
const opcoes = computed(() =>
  props.cupons.map(cupom => ({
    value: cupom.id,
    label: cupom.nome,
    hint: oferta(cupom.oferta, cupom.moeda),
  }))
);
const escolhido = computed(() =>
  props.cupons.find(cupom => cupom.id === props.modelValue.cupom_id)
);
const previa = computed(() => {
  const cupom = escolhido.value;
  if (!cupom) return '';
  return textoDeExemplo(props.modelValue.texto, {
    'cupom.codigo': exemploDeCodigo(cupom.prefixo),
    'cupom.oferta': oferta(cupom.oferta, cupom.moeda),
    'cupom.vale_ate': data(
      props.agora / 1000 + cupom.validade_dias * SEGUNDOS_POR_DIA,
      props.agora
    ),
    'contato.fidelidade_saldo': t(`${C}.EXEMPLO_SALDO`),
    'contato.fidelidade_faltam': t(`${C}.EXEMPLO_FALTAM`),
    'contato.fidelidade_premio': t(`${C}.EXEMPLO_PREMIO`),
  });
});
const semCodigo = computed(() => faltaOCodigo(props.modelValue));
const catalogoComCupom = computed(() => comValoresDoCupom(props.catalogo));
</script>

<template>
  <div class="flex flex-col gap-5" data-passo-novo="mandar_cupom">
    <div
      v-if="!cupons.length"
      data-fidelidade="sem-cupom"
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-amber-2 text-n-amber-12"
    >
      <p class="m-0 text-[0.9375rem] font-medium">{{ t(`${C}.SEM_CUPOM`) }}</p>
      <Button
        class="self-start min-h-11"
        color="amber"
        icon="i-lucide-ticket-percent"
        :label="t(`${C}.CRIAR`)"
        @click="emit('criarCupom')"
      />
    </div>

    <template v-else>
      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t(`${C}.QUAL`) }}
        </span>
        <ChoiceSelect
          data-fidelidade="qual-cupom"
          :model-value="modelValue.cupom_id"
          :aria-label="t(`${C}.QUAL`)"
          :placeholder="t(`${C}.ESCOLHA`)"
          :options="opcoes"
          @update:model-value="cupom_id => mudar({ cupom_id })"
        />
      </div>

      <LivreTexto
        :rotulo="t(`${C}.MENSAGEM`)"
        :model-value="modelValue.texto"
        :catalogo="catalogoComCupom"
        :atributos-do="atributosDo"
        :rotulo-do-dado="t(`${C}.POR_DADO`)"
        :dica="t(`${C}.TEXTO_DICA`)"
        @update:model-value="texto => mudar({ texto })"
      />

      <p
        v-if="semCodigo"
        data-fidelidade="sem-codigo"
        role="alert"
        class="px-4 py-3 m-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ t(`${C}.SEM_CODIGO`) }}
      </p>

      <figure
        v-if="previa"
        data-fidelidade="previa-mensagem"
        class="flex flex-col gap-2 p-4 m-0 rounded-2xl bg-n-alpha-2"
      >
        <figcaption class="text-sm font-medium text-n-slate-11">
          {{ t(`${C}.PREVIA`) }}
        </figcaption>
        <p
          class="self-start max-w-sm px-3 py-2 m-0 text-[0.9375rem] shadow-sm whitespace-pre-line rounded-2xl rounded-ss-sm bg-n-teal-3 text-n-slate-12"
        >
          {{ previa }}
        </p>
      </figure>

      <LivreModelo
        :rotulo="t(`${JANELA}.ROTULO`)"
        :model-value="modelValue.modelo || null"
        :catalogo="catalogoComCupom"
        :atributos-do="atributosDo"
        :textos="TEXTOS_DA_JANELA"
        @update:model-value="modelo => mudar({ modelo })"
      />

      <p class="m-0 text-sm text-n-slate-11">{{ t(`${C}.REGRAS`) }}</p>
    </template>
  </div>
</template>
