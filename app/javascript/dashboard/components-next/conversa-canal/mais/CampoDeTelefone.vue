<script setup>
// Telefone do contato no "+" (#1702): país com bandeira e DDI (Brasil por
// padrão) e o número formatado do jeito daquele país enquanto digita. O valor
// (v-model) é o número completo (+5511987654321), ou vazio enquanto não for um
// número válido do país escolhido. Digitar ou colar com + troca o país sozinho
// assim que o código fica claro.
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
  posicaoDepoisDosDigitos,
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
// Texto com + cujo país ainda não dá para saber ("+", "+1"): fica como está.
const cru = ref('');
let ultimoEnviado = '';

const formatado = computed(
  () => cru.value || formatarNoPais(digitos.value, pais.value)
);
const exemplo = computed(() => exemploDoPais(pais.value));
const idDaMensagem = `${id}-mensagem`;

const enviar = () => {
  ultimoEnviado = cru.value ? '' : telefoneCompleto(digitos.value, pais.value);
  telefone.value = ultimoEnviado;
};

const aplicar = separado => {
  pais.value = separado.pais;
  digitos.value = separado.digitos.slice(0, MAXIMO_DE_DIGITOS);
  cru.value = separado.cru;
};

// Número que chega de fora (contato escolhido da base).
watch(
  telefone,
  valor => {
    if (valor === ultimoEnviado) return;
    ultimoEnviado = valor;
    aplicar(separarTelefone(valor, pais.value));
  },
  { immediate: true }
);

const trocarPais = () => {
  cru.value = '';
  enviar();
};

// Apagar logo depois de um separador ("(11) |9…"): os dígitos não mudam, então
// apaga o dígito anterior, como a pessoa espera.
const apagouSoOSeparador = (evento, novos, antes) =>
  evento.inputType === 'deleteContentBackward' && novos === antes;

const aoDigitar = evento => {
  if (evento.isComposing) return;
  const campo = evento.target;
  const texto = campo.value;
  const cursor = campo.selectionStart ?? texto.length;

  if (texto.trim().startsWith('+')) {
    aplicar(separarTelefone(texto, pais.value));
    enviar();
    if (cru.value) return;
    campo.value = formatado.value;
    campo.setSelectionRange?.(formatado.value.length, formatado.value.length);
    return;
  }

  let antesDoCursor = soDigitosDoTelefone(texto.slice(0, cursor)).length;
  let novos = soDigitosDoTelefone(texto);
  if (apagouSoOSeparador(evento, novos, digitos.value) && antesDoCursor > 0) {
    novos = novos.slice(0, antesDoCursor - 1) + novos.slice(antesDoCursor);
    antesDoCursor -= 1;
  }
  cru.value = '';
  digitos.value = novos.slice(0, MAXIMO_DE_DIGITOS);
  enviar();
  // Letra digitada não entra: o campo volta ao número formatado, com o cursor
  // depois do mesmo dígito em que estava.
  campo.value = formatado.value;
  const posicao = posicaoDepoisDosDigitos(formatado.value, antesDoCursor);
  campo.setSelectionRange?.(posicao, posicao);
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
        :aria-invalid="Boolean(erro) || undefined"
        :aria-describedby="erro || ajuda ? idDaMensagem : undefined"
        class="flex-1"
        data-numero-do-telefone
        @input="aoDigitar"
      />
    </div>
    <p
      v-if="erro || ajuda"
      :id="idDaMensagem"
      aria-live="polite"
      class="min-w-0 mt-1 mb-0 text-label-small"
      :class="erro ? 'text-n-ruby-9' : 'text-n-slate-11'"
    >
      {{ erro || ajuda }}
    </p>
  </div>
</template>
