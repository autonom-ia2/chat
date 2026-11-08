<script setup>
import { computed, useId } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  FILTROS_VAZIOS,
  algumFiltroLigado,
} from '../../../utils/desempenhoDetalhe';

// #2226 v2 — busca, as escolhas e os interruptores da tabela de procuras. Cada mudança devolve um
// objeto novo de filtros (nada é alterado no lugar).
const props = defineProps({
  filtros: { type: Object, required: true },
  // Saída de opcoesDosFiltros()
  opcoes: { type: Object, required: true },
  // O nome da IA ("Como Duda foi").
  nome: { type: String, default: '' },
});

const emit = defineEmits(['update:filtros']);
const { t } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.FILTROS';
const id = useId();

const mudar = (chave, valor) =>
  emit('update:filtros', { ...props.filtros, [chave]: valor });

const escolhas = computed(() => [
  { chave: 'tema', rotulo: t(`${B}.TEMA`), options: props.opcoes.temas },
  {
    chave: 'resultado',
    rotulo: t(`${B}.RESULTADO`),
    groups: props.opcoes.resultados,
  },
  { chave: 'marco', rotulo: t(`${B}.MARCO`), options: props.opcoes.marcos },
  {
    chave: 'qualidade',
    rotulo: t(`${B}.QUALIDADE.ROTULO`, { nome: props.nome }),
    options: props.opcoes.qualidades,
  },
  { chave: 'origem', rotulo: t(`${B}.ORIGEM`), options: props.opcoes.origens },
  { chave: 'corte', rotulo: t(`${B}.CORTE`), groups: props.opcoes.cortes },
]);

const interruptores = computed(() => [
  { chave: 'perda', rotulo: t(`${B}.SO_PERDAS`) },
  { chave: 'pessoa', rotulo: t(`${B}.SO_PESSOA`) },
  { chave: 'testes', rotulo: t(`${B}.MOSTRAR_TESTES`) },
]);

const ligado = computed(() => algumFiltroLigado(props.filtros));
const limpar = () =>
  emit('update:filtros', { ...props.filtros, ...FILTROS_VAZIOS });
</script>

<template>
  <div class="flex flex-col gap-3" role="search">
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1 w-full md:w-72">
        <label
          :for="`${id}-busca`"
          class="text-xs font-semibold text-n-slate-11"
        >
          {{ t(`${B}.BUSCA`) }}
        </label>
        <Input
          :id="`${id}-busca`"
          :model-value="filtros.busca"
          type="search"
          size="sm"
          :placeholder="t(`${B}.BUSCA_DICA`)"
          @update:model-value="mudar('busca', $event)"
        />
      </div>
      <div
        v-for="escolha in escolhas"
        :key="escolha.chave"
        class="flex flex-col gap-1 min-w-[9rem] max-w-[16rem]"
      >
        <label
          :for="`${id}-${escolha.chave}`"
          class="text-xs font-semibold text-n-slate-11"
        >
          {{ escolha.rotulo }}
        </label>
        <ChoiceSelect
          :model-value="filtros[escolha.chave]"
          compact
          :trigger-id="`${id}-${escolha.chave}`"
          :options="escolha.options || []"
          :groups="escolha.groups || []"
          :aria-label="escolha.rotulo"
          :data-filtro="escolha.chave"
          @update:model-value="mudar(escolha.chave, $event)"
        />
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <button
        v-for="item in interruptores"
        :key="item.chave"
        type="button"
        :aria-pressed="Boolean(filtros[item.chave])"
        :data-interruptor="item.chave"
        class="inline-flex items-center gap-2 min-h-11 px-3 rounded-full text-sm ring-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          filtros[item.chave]
            ? 'bg-n-blue-3 text-n-blue-11 ring-n-blue-7 font-semibold'
            : 'bg-n-solid-1 text-n-slate-11 ring-n-weak hover:bg-n-alpha-1'
        "
        @click="mudar(item.chave, !filtros[item.chave])"
      >
        <span
          class="size-4 flex-shrink-0"
          :class="filtros[item.chave] ? 'i-lucide-check' : 'i-lucide-plus'"
          aria-hidden="true"
        />
        {{ item.rotulo }}
      </button>
      <Button
        v-if="ligado"
        size="sm"
        variant="link"
        color="slate"
        icon="i-lucide-x"
        class="min-h-11"
        :label="t(`${B}.LIMPAR`)"
        data-limpar
        @click="limpar"
      />
    </div>
  </div>
</template>
