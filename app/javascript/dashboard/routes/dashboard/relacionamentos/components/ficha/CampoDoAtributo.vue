<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { attributeDate } from 'dashboard/helper/attributeDate';
import { temValor } from '../../ficha/atributos';
import { useIdioma } from '../../ficha/idioma';
import {
  exemploDaData,
  textoDaData,
  valorDaData,
} from '../../ficha/dataDoCampo';
import CampoDeTexto from './CampoDeTexto.vue';

// #3075 — um campo personalizado na gaveta, com o controle do tipo dele:
//  - texto e link: campo de texto (o link aceita "seusite.com.br"; o
//    "https://" entra ao salvar);
//  - número: campo de número (sobe como número). O que o navegador não
//    consegue ler como número é ignorado: o valor só fica vazio quando o campo
//    está vazio de verdade;
//  - data (#3082): escrita no formato do idioma do painel ("dd/mm/aaaa" em
//    português), e não no do navegador; o botão "Calendário" abre o calendário
//    do navegador. Sobe como "AAAA-MM-DD", o formato que a ficha grava. A data
//    gravada em outro formato (por importação, por exemplo) aparece como está,
//    para não se perder sem ninguém ver;
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
const idioma = useIdioma();
const ga = (chave, params) =>
  t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`, params);

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

const ehData = computed(() => props.campo.tipo === 'date');
const temLimpar = computed(
  () => (ehEscolha.value || ehData.value) && temValor(props.valor)
);

// A data em "AAAA-MM-DD" para o calendário ('' quando o texto não é uma data).
const dataDoCalendario = computed(() =>
  ehData.value ? attributeDate(props.valor) : ''
);
const exemplo = computed(() =>
  exemploDaData(idioma.value, {
    day: ga('ATRIBUTO.DATA_DIA'),
    month: ga('ATRIBUTO.DATA_MES'),
    year: ga('ATRIBUTO.DATA_ANO'),
  })
);
const calendario = ref(null);
// O calendário do navegador abre por um campo de data escondido.
const abrirCalendario = () => {
  const campo = calendario.value;
  if (!campo) return;
  if (typeof campo.showPicker === 'function') campo.showPicker();
  else campo.click();
};

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
  if (ehData.value)
    return { type: 'text', inputmode: 'numeric', placeholder: exemplo.value };
  return PELO_TIPO[props.campo.tipo] ?? { type: 'text' };
});

const textoNoCampo = computed(() => {
  if (!temValor(props.valor)) return '';
  return ehData.value
    ? textoDaData(props.valor, idioma.value)
    : String(props.valor);
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
  emit('mudar', ehData.value ? valorDaData(texto, idioma.value) : texto);
};

const vaiSair = computed(
  () => temValor(props.valorInicial) && !temValor(props.valor)
);
const ajuda = computed(() => (vaiSair.value ? ga('ATRIBUTO.VAI_SAIR') : ''));
const mensagem = computed(() =>
  props.erro ? ga(`ERRO.${props.erro}`, { formato: exemplo.value }) : ''
);
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
      <template v-if="temLimpar || ehData" #acao>
        <div class="flex items-center shrink-0 -my-2 -me-3">
          <template v-if="ehData">
            <Button
              data-relacionamentos="calendario-do-atributo"
              slate
              ghost
              type="button"
              icon="i-lucide-calendar-days"
              class="!h-11 shrink-0"
              :label="ga('ATRIBUTO.CALENDARIO')"
              :aria-label="
                ga('ATRIBUTO.CALENDARIO_DE', {
                  campo: campo.rotulo,
                })
              "
              @click="abrirCalendario"
            />
            <input
              ref="calendario"
              data-relacionamentos="calendario-escondido"
              type="date"
              tabindex="-1"
              aria-hidden="true"
              class="sr-only"
              :value="dataDoCalendario"
              @change="evento => emit('mudar', evento.target.value)"
            />
          </template>
          <Button
            v-if="temLimpar"
            data-relacionamentos="limpar-atributo"
            slate
            ghost
            type="button"
            icon="i-lucide-eraser"
            class="!h-11 shrink-0"
            :label="ga('ATRIBUTO.LIMPAR')"
            :aria-label="
              t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.LIMPAR_O', {
                campo: campo.rotulo,
              })
            "
            @click="emit('mudar', '')"
          />
        </div>
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
