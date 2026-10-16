<script setup>
// Telefone do contato no "+" (#1702): país com bandeira e DDI (Brasil por
// padrão) e o número formatado do jeito daquele país enquanto digita. O valor
// (v-model) é o número completo (+5511987654321), ou vazio enquanto não for um
// número válido do país escolhido. Colar um número com + troca o país sozinho.
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'next/choice-select/ChoiceSelect.vue';
import Input from 'next/input/Input.vue';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  PAIS_PADRAO,
  exemploDoPais,
  formatarNoPais,
  paisesDoTelefone,
  separarTelefone,
  soDigitosDoTelefone,
  telefoneCompleto,
} from './telefoneDoPais';

const props = defineProps({
  label: { type: String, required: true },
  rotuloDoPais: { type: String, required: true },
  ajuda: { type: String, default: '' },
  erro: { type: String, default: '' },
});

const telefone = defineModel({ type: String, default: '' });

// O maior número do plano internacional (E.164) tem 15 dígitos.
const MAXIMO_DE_DIGITOS = 15;

const { locale } = useI18n();
const id = useId();
const paises = computed(() => paisesDoTelefone(idiomaDoPainel(locale.value)));

const pais = ref(PAIS_PADRAO);
const digitos = ref('');
let ultimoEnviado = '';

const formatado = computed(() => formatarNoPais(digitos.value, pais.value));
const exemplo = computed(() => exemploDoPais(pais.value));

const enviar = () => {
  ultimoEnviado = telefoneCompleto(digitos.value, pais.value);
  telefone.value = ultimoEnviado;
};

// Número que chega de fora (contato escolhido da base, janela limpa).
watch(
  telefone,
  valor => {
    if (valor === ultimoEnviado) return;
    ultimoEnviado = valor;
    const separado = separarTelefone(valor, pais.value);
    pais.value = separado.pais;
    digitos.value = separado.digitos;
  },
  { immediate: true }
);

const trocarPais = () => enviar();

const aoDigitar = evento => {
  const texto = evento.target.value;
  if (texto.trim().startsWith('+')) {
    const separado = separarTelefone(texto, pais.value);
    pais.value = separado.pais;
    digitos.value = separado.digitos.slice(0, MAXIMO_DE_DIGITOS);
  } else {
    digitos.value = soDigitosDoTelefone(texto).slice(0, MAXIMO_DE_DIGITOS);
  }
  enviar();
  // Letra digitada não entra: o campo volta ao número formatado.
  evento.target.value = formatado.value;
};
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <label :for="id" class="mb-0.5 text-heading-3 text-n-slate-12">
      {{ props.label }}
    </label>
    <div class="flex items-start gap-2 min-w-0">
      <div class="w-[7.5rem] flex-shrink-0">
        <ChoiceSelect
          v-model="pais"
          :options="paises"
          :aria-label="rotuloDoPais"
          :invalid="Boolean(erro)"
          @change="trocarPais"
        />
      </div>
      <Input
        :id="id"
        :model-value="formatado"
        type="tel"
        inputmode="tel"
        autocomplete="tel-national"
        :placeholder="exemplo"
        :message-type="erro ? 'error' : 'info'"
        class="flex-1"
        data-numero-do-telefone
        @input="aoDigitar"
      />
    </div>
    <p
      v-if="erro || ajuda"
      class="min-w-0 mt-1 mb-0 text-label-small"
      :class="erro ? 'text-n-ruby-9' : 'text-n-slate-11'"
    >
      {{ erro || ajuda }}
    </p>
  </div>
</template>
