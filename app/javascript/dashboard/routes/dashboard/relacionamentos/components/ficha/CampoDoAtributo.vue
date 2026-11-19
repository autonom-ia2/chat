<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { attributeDate } from 'dashboard/helper/attributeDate';
import { temValor } from '../../ficha/atributos';
import CampoDeTexto from './CampoDeTexto.vue';

// #3075 — um campo personalizado na gaveta, com o controle do tipo dele:
//  - texto e link: campo de texto (o link pede o endereço com https://);
//  - número: campo de número (sobe como número);
//  - data: o campo de data do navegador, como o resto da ficha (sobe como
//    "AAAA-MM-DD", o formato que a ficha antiga grava);
//  - lista e "sim ou não": a escolha da casa (ChoiceSelect), sem <select>.
// "Apagar" aparece quando o campo tem valor e o esvazia; a linha de baixo diz
// que ele fica em branco quando a pessoa salvar. Não altera nada: cada mudança
// sobe por `mudar`.
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

const PELO_TIPO = {
  link: { type: 'url', inputmode: 'url', placeholder: 'https://' },
  number: { type: 'number', inputmode: 'decimal', step: 'any' },
  date: { type: 'date' },
};
const atributosDoCampo = computed(() => PELO_TIPO[props.campo.tipo] ?? {});

const textoNoCampo = computed(() => {
  if (!temValor(props.valor)) return '';
  return props.campo.tipo === 'date'
    ? attributeDate(props.valor)
    : String(props.valor);
});

const aoEscrever = texto => {
  if (props.campo.tipo === 'number' && texto !== '') {
    emit('mudar', Number(texto));
    return;
  }
  emit('mudar', texto);
};

const vaiSair = computed(
  () => temValor(props.valorInicial) && !temValor(props.valor)
);
const ajuda = computed(() => (vaiSair.value ? ga('ATRIBUTO.VAI_SAIR') : ''));
const mensagem = computed(() => (props.erro ? ga(`ERRO.${props.erro}`) : ''));
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
          v-if="temValor(valor)"
          data-relacionamentos="apagar-atributo"
          slate
          ghost
          type="button"
          icon="i-lucide-eraser"
          class="!h-11 -my-2 -me-3 shrink-0"
          :label="ga('ATRIBUTO.APAGAR')"
          :aria-label="
            t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.APAGAR_O', {
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
      v-bind="atributosDoCampo"
      @update:model-value="aoEscrever"
    >
      <template v-if="temValor(valor)" #acao>
        <Button
          data-relacionamentos="apagar-atributo"
          slate
          ghost
          type="button"
          icon="i-lucide-eraser"
          class="!h-11 -my-2 -me-3 shrink-0"
          :label="ga('ATRIBUTO.APAGAR')"
          :aria-label="
            t('RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.APAGAR_O', {
              campo: campo.rotulo,
            })
          "
          @click="emit('mudar', '')"
        />
      </template>
    </CampoDeTexto>
  </div>
</template>
