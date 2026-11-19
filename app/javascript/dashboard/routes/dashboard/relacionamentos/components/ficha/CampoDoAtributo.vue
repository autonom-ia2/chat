<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { attributeDate } from 'dashboard/helper/attributeDate';
import { temValor } from '../../ficha/atributos';
import CampoDeTexto from './CampoDeTexto.vue';

// #3075 — um campo personalizado na gaveta, com o controle do tipo dele:
//  - texto e link: campo de texto (o link aceita "seusite.com.br"; o
//    "https://" entra ao salvar);
//  - número: campo de número (sobe como número). O que o navegador não
//    consegue ler como número é ignorado: o valor só fica vazio quando o campo
//    está vazio de verdade;
//  - data: o campo de data do navegador, como o resto da ficha (sobe como
//    "AAAA-MM-DD", o formato que a ficha antiga grava). A data gravada em outro
//    formato (por importação, por exemplo) aparece como está, num campo de
//    texto: o campo de data não a mostraria, e ela se perderia sem ninguém ver;
//  - lista e "sim ou não": a escolha da casa (ChoiceSelect), sem <select>.
// "Limpar" (só na data, na lista e no "sim ou não", onde não dá para apagar
// escrevendo) esvazia o campo. Quando o campo tinha valor e ficou vazio, a
// linha de baixo diz que ele fica em branco ao salvar, e "Voltar como estava"
// devolve o valor de quando a gaveta abriu. Não altera nada: cada mudança sobe
// por `mudar`.
const props = defineProps({
  // { chave, rotulo, tipo, opcoes }.
  campo: { type: Object, required: true },
  valor: { type: [String, Number, Boolean], default: '' },
  valorInicial: { type: [String, Number, Boolean], default: '' },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['mudar']);

const { t } = useI18n();
const id = useId();
const ga = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);

const ehEscolha = computed(() =>
  ['list', 'checkbox'].includes(props.campo.tipo)
);
const opcoes = computed(() =>
  props.campo.tipo === 'checkbox'
    ? [
        { value: true, label: ga('ATRIBUTO.SIM') },
        { value: false, label: ga('ATRIBUTO.NAO') },
      ]
    : props.campo.opcoes.map(opcao => ({ value: opcao, label: opcao }))
);

// A data que o campo de data consegue mostrar ('' se não há ou não serve).
const dataDoCampo = computed(() =>
  props.campo.tipo === 'date' ? attributeDate(props.valor) : ''
);
const dataEmOutroFormato = computed(
  () =>
    props.campo.tipo === 'date' && temValor(props.valor) && !dataDoCampo.value
);
const ehData = computed(
  () => props.campo.tipo === 'date' && !dataEmOutroFormato.value
);
const temLimpar = computed(
  () => (ehEscolha.value || ehData.value) && temValor(props.valor)
);

const PELO_TIPO = {
  link: {
    type: 'url',
    inputmode: 'url',
    autocapitalize: 'off',
    placeholder: ga('ATRIBUTO.LINK_EXEMPLO'),
  },
  number: { type: 'number', inputmode: 'decimal', step: 'any' },
};
const atributosDoCampo = computed(() => {
  if (ehData.value) return { type: 'date' };
  return PELO_TIPO[props.campo.tipo] ?? { type: 'text' };
});

const textoNoCampo = computed(() => {
  if (!temValor(props.valor)) return '';
  return ehData.value ? dataDoCampo.value : String(props.valor);
});

// O número vem do próprio campo: com letra no meio o navegador entrega '' e
// marca `badInput`, e isso não pode apagar o valor.
const aoDigitarNumero = evento => {
  const alvo = evento.target;
  if (alvo.validity?.badInput) return;
  emit('mudar', alvo.value === '' ? '' : Number(alvo.value));
};
const ouvintes = computed(() =>
  props.campo.tipo === 'number' ? { onInput: aoDigitarNumero } : {}
);
const aoEscrever = texto => {
  if (props.campo.tipo === 'number') return;
  emit('mudar', texto);
};

const vaiSair = computed(
  () => temValor(props.valorInicial) && !temValor(props.valor)
);
const ajuda = computed(() => (vaiSair.value ? ga('ATRIBUTO.VAI_SAIR') : ''));
const mensagem = computed(() => (props.erro ? ga(`ERRO.${props.erro}`) : ''));
const voltar = () => emit('mudar', props.valorInicial);
</script>

<template>
  <div :data-atributo="campo.chave" class="flex flex-col min-w-0">
    <template v-if="ehEscolha">
      <div class="flex items-center justify-between min-w-0 gap-3 mb-1.5">
        <label
          :for="`${id}-escolha`"
          class="min-w-0 break-words text-heading-3 text-n-slate-12"
        >
          {{ campo.rotulo }}
        </label>
        <Button
          v-if="temLimpar"
          data-relacionamentos="limpar-atributo"
          slate
          ghost
          type="button"
          icon="i-lucide-eraser"
          class="!h-11 -my-2 -me-3 shrink-0"
          :label="ga('ATRIBUTO.LIMPAR')"
          :aria-label="
            t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.LIMPAR_O', {
              campo: campo.rotulo,
            })
          "
          @click="emit('mudar', '')"
        />
      </div>
      <ChoiceSelect
        :model-value="temValor(valor) ? valor : ''"
        :options="opcoes"
        :trigger-id="`${id}-escolha`"
        :aria-label="campo.rotulo"
        :placeholder="ga('ATRIBUTO.ESCOLHA')"
        :described-by="vaiSair ? `${id}-ajuda` : undefined"
        wrap-selected
        class="w-full"
        @update:model-value="escolhida => emit('mudar', escolhida)"
      />
      <p
        v-if="ajuda"
        :id="`${id}-ajuda`"
        class="mt-2 mb-0 text-sm text-n-slate-11"
        data-relacionamentos="ajuda-do-campo"
      >
        {{ ajuda }}
      </p>
    </template>
    <CampoDeTexto
      v-else
      :model-value="textoNoCampo"
      :rotulo="campo.rotulo"
      :erro="mensagem"
      :ajuda="ajuda"
      v-bind="{ ...atributosDoCampo, ...ouvintes }"
      @update:model-value="aoEscrever"
    >
      <template v-if="temLimpar" #acao>
        <Button
          data-relacionamentos="limpar-atributo"
          slate
          ghost
          type="button"
          icon="i-lucide-eraser"
          class="!h-11 -my-2 -me-3 shrink-0"
          :label="ga('ATRIBUTO.LIMPAR')"
          :aria-label="
            t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.LIMPAR_O', {
              campo: campo.rotulo,
            })
          "
          @click="emit('mudar', '')"
        />
      </template>
    </CampoDeTexto>
    <Button
      v-if="vaiSair"
      data-relacionamentos="voltar-atributo"
      slate
      ghost
      type="button"
      class="!h-11 mt-1 -ms-3 self-start"
      :label="ga('FOTO.MANTER')"
      @click="voltar"
    />
  </div>
</template>
