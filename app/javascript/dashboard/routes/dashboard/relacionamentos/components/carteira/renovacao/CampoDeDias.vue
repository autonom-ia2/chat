<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  diasDigitados,
  umDiaAMais,
  umDiaAMenos,
} from '../../../carteira/ajustesDaRenovacao';

// #2897 — quantos dias antes: o número no meio e um botão de cada lado (menos e
// mais), cada um com 44 px. Aceita qualquer número inteiro a partir de 1; o que
// não é número vira `null`, e quem usa diz o que falta.
const props = defineProps({
  modelValue: { type: Number, default: null },
  id: { type: String, required: true },
  invalido: { type: Boolean, default: false },
  descritoPor: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const to = chave => t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.ONDE.${chave}`);
const texto = ref(String(props.modelValue ?? ''));

// O número mudou por fora (os botões, outra escolha): o campo acompanha. O que
// a pessoa está escrevendo e ainda não é número fica como está.
watch(
  () => props.modelValue,
  novo => {
    if (novo !== diasDigitados(texto.value)) texto.value = String(novo ?? '');
  }
);

const aoEscrever = evento => {
  texto.value = evento.target.value;
  emit('update:modelValue', diasDigitados(texto.value));
};

const BOTAO =
  'inline-flex items-center justify-center size-11 shrink-0 rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <div class="flex items-center gap-2">
    <button
      type="button"
      data-dias="menos"
      :class="BOTAO"
      :aria-label="to('DIAS_MENOS')"
      @click="emit('update:modelValue', umDiaAMenos(modelValue))"
    >
      <span class="i-lucide-minus size-5" aria-hidden="true" />
    </button>
    <input
      :id="id"
      type="text"
      inputmode="numeric"
      autocomplete="off"
      :value="texto"
      :aria-invalid="invalido ? 'true' : undefined"
      :aria-describedby="descritoPor"
      class="block w-20 px-3 text-lg font-semibold text-center border-0 rounded-xl h-11 reset-base tabular-nums outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 focus:outline-n-brand"
      :class="invalido ? 'outline-n-ruby-8' : 'outline-n-weak'"
      @input="aoEscrever"
    />
    <button
      type="button"
      data-dias="mais"
      :class="BOTAO"
      :aria-label="to('DIAS_MAIS')"
      @click="emit('update:modelValue', umDiaAMais(modelValue))"
    >
      <span class="i-lucide-plus size-5" aria-hidden="true" />
    </button>
  </div>
</template>
