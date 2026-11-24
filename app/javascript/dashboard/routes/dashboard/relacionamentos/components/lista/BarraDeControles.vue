<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { breakpointsTailwind, useBreakpoints } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { ORDENS } from '../../fonte/listaFonte';
import CampoDeBusca from './CampoDeBusca.vue';

// #2894 — a faixa de controles acima da lista: busca, ordem e "Mais filtros".
// `comFiltros` falso tira o "Mais filtros" (#3078: a aba Empresas também tem
// os dela, cidade e quando chegou).
// #3057 — busca, ordem e "Mais filtros" na mesma altura (h-10) e no mesmo
// canto; a área de toque do botão continua com 44 px (o ::before).
// #3062 — `gruposDeOrdem` (lista/ordens.js): a aba Pessoas ganha as sete ordens
// da lista de contatos de hoje, agrupadas por campo e nos dois sentidos. Sem
// eles, ficam as três de sempre. No celular o rótulo "Ordenar" fica só para o
// leitor de tela, então o botão diz o que é: "Ordem: Nome, de A a Z".
// #3168 — `podeGuardarGrupo`: ao lado de "Mais filtros", "Guardar como grupo"
// (quem decide quando aparece é a tela). No celular ele ganha a última linha.
const props = defineProps({
  busca: { type: String, default: '' },
  ordem: { type: String, required: true },
  gruposDeOrdem: { type: Array, default: () => [] },
  filtrosAtivos: { type: Number, default: 0 },
  comFiltros: { type: Boolean, default: true },
  placeholder: { type: String, required: true },
  placeholderCurto: { type: String, default: '' },
  podeGuardarGrupo: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:busca',
  'update:ordem',
  'abrirFiltros',
  'guardarGrupo',
]);

const { t } = useI18n();
const idDaOrdem = useId();

const opcoesDeOrdem = computed(() => [
  {
    value: ORDENS.ULTIMA_CONVERSA,
    label: t('RELACIONAMENTOS.LISTA.ORDENAR.ULTIMA_CONVERSA'),
  },
  { value: ORDENS.NOME, label: t('RELACIONAMENTOS.LISTA.ORDENAR.NOME') },
  {
    value: ORDENS.MAIS_NOVOS,
    label: t('RELACIONAMENTOS.LISTA.ORDENAR.MAIS_NOVOS'),
  },
]);

const noCelular = useBreakpoints(breakpointsTailwind).smaller('sm');
const comNomeNoBotao = opcao => ({
  ...opcao,
  shortLabel: t('RELACIONAMENTOS.LISTA.ORDENAR.NO_BOTAO', {
    ordem: opcao.shortLabel ?? opcao.label,
  }),
});
const opcoesNaTela = computed(() =>
  noCelular.value
    ? opcoesDeOrdem.value.map(comNomeNoBotao)
    : opcoesDeOrdem.value
);
const gruposNaTela = computed(() =>
  noCelular.value
    ? props.gruposDeOrdem.map(grupo => ({
        ...grupo,
        options: grupo.options.map(comNomeNoBotao),
      }))
    : props.gruposDeOrdem
);

const rotuloDosFiltros = computed(() =>
  props.filtrosAtivos
    ? t('RELACIONAMENTOS.LISTA.FILTROS.BOTAO_COM_CONTAGEM', {
        count: props.filtrosAtivos,
      })
    : t('RELACIONAMENTOS.LISTA.FILTROS.BOTAO')
);
</script>

<template>
  <!-- No celular a busca divide a linha com "Mais filtros" e a ordem ganha a
  linha de baixo inteira: "Ordem: Conversa mais recente" cabe sem cortar. -->
  <div class="flex flex-wrap items-center min-w-0 gap-3">
    <CampoDeBusca
      class="flex-1 min-w-0 md:min-w-72"
      :model-value="busca"
      :placeholder="placeholder"
      :placeholder-curto="placeholderCurto"
      @update:model-value="emit('update:busca', $event)"
    />
    <div
      class="flex items-center order-last w-full min-w-0 gap-2 md:order-none md:w-auto"
    >
      <label
        :for="idDaOrdem"
        class="text-sm sr-only text-n-slate-11 sm:not-sr-only"
      >
        {{ t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO') }}
      </label>
      <ChoiceSelect
        :model-value="ordem"
        :options="gruposDeOrdem.length ? [] : opcoesNaTela"
        :groups="gruposNaTela"
        :trigger-id="idDaOrdem"
        :aria-label="t('RELACIONAMENTOS.LISTA.ORDENAR.ROTULO')"
        data-relacionamentos="ordem"
        class="flex-1 min-w-0 md:flex-none"
        @update:model-value="emit('update:ordem', $event)"
      />
    </div>
    <Button
      v-if="comFiltros"
      slate
      faded
      class="relative shrink-0 whitespace-nowrap before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5"
      icon="i-lucide-sliders-horizontal"
      data-relacionamentos="mais-filtros"
      aria-haspopup="dialog"
      :label="rotuloDosFiltros"
      @click="emit('abrirFiltros')"
    />
    <Button
      v-if="podeGuardarGrupo"
      slate
      faded
      class="relative order-last w-full shrink-0 whitespace-nowrap md:order-none md:w-auto before:absolute before:content-[''] before:inset-x-0 before:-inset-y-0.5"
      icon="i-lucide-bookmark-plus"
      data-relacionamentos="guardar-como-grupo"
      aria-haspopup="dialog"
      :label="t('RELACIONAMENTOS.LISTA.MEUS_GRUPOS.GUARDAR_COMO_GRUPO')"
      @click="emit('guardarGrupo')"
    />
  </div>
</template>
