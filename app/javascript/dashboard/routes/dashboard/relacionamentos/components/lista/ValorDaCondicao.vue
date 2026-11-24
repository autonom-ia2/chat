<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ChaveDeOpcoes from '../comum/ChaveDeOpcoes.vue';
import CampoDeTexto from '../ficha/CampoDeTexto.vue';
import CampoDoAtributo from '../ficha/CampoDoAtributo.vue';
import { OPERADORES, TIPOS } from '../../lista/informacoes';
import { useIdioma } from '../../ficha/idioma';
import { textoDaData } from '../../ficha/dataDoCampo';

// #3168 — o valor de uma linha de "Por outra informação", com o campo certo
// para o tipo: texto (ou número) para escrever; lista na escolha da casa
// (etiquetas e países acham pela letra digitada); data igual à da ficha
// (CampoDoAtributo: formato do idioma e botão Calendário); "há mais de … dias"
// pede o número de dias; "sim ou não" vira Sim | Não. `erro` é o código de
// lista/informacoes.js (erroDaCondicao), mostrado embaixo do campo (em
// ruby-11, o tom com contraste para texto pequeno). A data traz de exemplo o
// Natal deste ano escrito no formato do idioma do painel ("Ex.: 25/12/2026").
const props = defineProps({
  condicao: { type: Object, required: true },
  // As opções da informação escolhida (lista), [{ value, label }].
  opcoes: { type: Array, default: () => [] },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['mudar']);

const { t } = useI18n();
const id = useId();
const CV = 'RELACIONAMENTOS.LISTA.CONDICOES';

const ehDias = computed(
  () => props.condicao.como === OPERADORES.HA_MAIS_DE_DIAS
);
const ehData = computed(
  () =>
    !ehDias.value &&
    [TIPOS.DATA, TIPOS.DATA_DA_CONTA].includes(props.condicao.tipo)
);
const ehLista = computed(() => props.condicao.tipo === TIPOS.LISTA);
const ehSimNao = computed(() => props.condicao.tipo === TIPOS.SIM_NAO);
const ehNumero = computed(
  () => ehDias.value || props.condicao.tipo === TIPOS.NUMERO
);

const rotulo = computed(() => {
  if (ehDias.value) return t(`${CV}.VALOR.DIAS`);
  if (ehData.value) return t(`${CV}.VALOR.DATA`);
  if (ehLista.value) return t(`${CV}.VALOR.LISTA`);
  if (ehSimNao.value) return t(`${CV}.VALOR.SIM_NAO`);
  return t(`${CV}.VALOR.TEXTO`);
});
const mensagem = computed(() =>
  props.erro && props.erro !== 'DATA_ERRADA'
    ? t(`${CV}.ERRO.${props.erro}`)
    : ''
);
const simNao = computed(() => [
  { value: true, label: t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.SIM') },
  { value: false, label: t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.NAO') },
]);
const campoDeData = computed(() => ({
  chave: props.condicao.chave,
  rotulo: rotulo.value,
  tipo: 'date',
  opcoes: [],
}));
const valorEmTexto = computed(() =>
  props.condicao.valor === null || props.condicao.valor === undefined
    ? ''
    : String(props.condicao.valor)
);
const idioma = useIdioma();
const exemploDeData = computed(() =>
  t(`${CV}.EXEMPLO_DE_DATA`, {
    data: textoDaData(`${new Date().getFullYear()}-12-25`, idioma.value),
  })
);
const atributosDoNumero = { type: 'number', inputmode: 'numeric', min: '1' };
</script>

<template>
  <div class="flex flex-col min-w-0" data-relacionamentos="valor-da-condicao">
    <template v-if="ehLista">
      <label :for="`${id}-lista`" class="mb-1.5 text-heading-3 text-n-slate-12">
        {{ rotulo }}
      </label>
      <ChoiceSelect
        :model-value="condicao.valor"
        :options="opcoes"
        :trigger-id="`${id}-lista`"
        :aria-label="rotulo"
        :placeholder="t(`${CV}.ESCOLHA_UMA_OPCAO`)"
        :invalid="Boolean(mensagem)"
        :described-by="mensagem ? `${id}-erro` : undefined"
        wrap-selected
        class="w-full"
        @update:model-value="emit('mudar', $event)"
      />
      <p
        :id="`${id}-erro`"
        aria-live="polite"
        class="mb-0 text-sm text-n-ruby-11"
        :class="mensagem ? 'mt-2' : 'mt-0'"
      >
        {{ mensagem }}
      </p>
    </template>
    <ChaveDeOpcoes
      v-else-if="ehSimNao"
      :model-value="condicao.valor === false ? false : true"
      :opcoes="simNao"
      :rotulo="rotulo"
      rotulo-escondido
      @update:model-value="emit('mudar', $event)"
    />
    <CampoDoAtributo
      v-else-if="ehData"
      :campo="campoDeData"
      :valor="valorEmTexto"
      :erro="erro === 'DATA_ERRADA' ? 'DATA' : ''"
      :texto-do-erro="mensagem"
      :exemplo-do-campo="exemploDeData"
      @mudar="emit('mudar', $event)"
    />
    <CampoDeTexto
      v-else-if="ehNumero"
      :model-value="valorEmTexto"
      :rotulo="rotulo"
      :erro="mensagem"
      v-bind="atributosDoNumero"
      @update:model-value="emit('mudar', $event)"
    />
    <CampoDeTexto
      v-else
      :model-value="valorEmTexto"
      :rotulo="rotulo"
      :erro="mensagem"
      @update:model-value="emit('mudar', $event)"
    />
  </div>
</template>
