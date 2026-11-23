<script setup>
import { computed, ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { useFocoPreso } from 'dashboard/components-next/NovaConversa/useFocoPreso';
import {
  COMPRAS,
  DIAS_DAS_COMPRAS,
  FIDELIDADE,
  FILTROS_VAZIOS,
  PERIODOS_DE_CHEGADA,
  TOTAIS_ACIMA,
} from '../../lista/filtros';
import { formatarDinheiro } from '../../ficha/compras';
import { useIdioma } from '../../ficha/idioma';

// #2894 — "Mais filtros": gaveta à direita com foco preso (useFocoPreso, a
// mesma da gaveta de Nova conversa), Esc fecha e o foco volta ao botão que
// abriu. "Ver resultado" aplica; "Limpar" tira todos e fecha. Campo que só
// teria "Todas" (Empresa numa conta sem empresas) não aparece.
// #3078 — na aba Empresas (`deEmpresas`) a gaveta tem só os filtros que a
// empresa tem: a cidade (as cidades das empresas, `cidades_das_empresas`) e
// quando chegou.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  deEmpresas: { type: Boolean, default: false },
  // #3097: sem ver valor de venda, sem o filtro do total comprado.
  veValores: { type: Boolean, default: false },
  // #3100: com o cartão fidelidade na conta (ou o filtro já ligado), o filtro dele.
  comFidelidade: { type: Boolean, default: false },
  filtros: { type: Object, default: () => ({ ...FILTROS_VAZIOS }) },
  opcoes: {
    type: Object,
    default: () => ({ empresas: [], etiquetas: [], cidades: [] }),
  },
});
const emit = defineEmits(['fechar', 'aplicar', 'limpar']);

const { t } = useI18n();
const idDoTitulo = useId();
const idBase = useId();
const raiz = useTemplateRef('raiz');
const { prender } = useFocoPreso(
  raiz,
  computed(() => props.aberta)
);

const rascunho = ref({ ...FILTROS_VAZIOS });
watch(
  () => props.aberta,
  aberta => {
    if (aberta) rascunho.value = { ...FILTROS_VAZIOS, ...props.filtros };
  },
  { immediate: true }
);

const comTodas = lista => [
  { value: '', label: t('RELACIONAMENTOS.LISTA.FILTROS.TODAS') },
  ...lista,
];

const periodos = computed(() => [
  { value: '', label: t('RELACIONAMENTOS.LISTA.FILTROS.QUALQUER_DATA') },
  {
    value: PERIODOS_DE_CHEGADA.ULTIMOS_7,
    label: t('RELACIONAMENTOS.LISTA.FILTROS.ULTIMOS_7'),
  },
  {
    value: PERIODOS_DE_CHEGADA.ULTIMOS_30,
    label: t('RELACIONAMENTOS.LISTA.FILTROS.ULTIMOS_30'),
  },
  {
    value: PERIODOS_DE_CHEGADA.ULTIMOS_90,
    label: t('RELACIONAMENTOS.LISTA.FILTROS.ULTIMOS_90'),
  },
]);

// #3097 — compras e total comprado (só em Pessoas). O total vai em faixas
// prontas: o leigo escolhe, não digita valor.
const idioma = useIdioma();
const FC = 'RELACIONAMENTOS_COMPRAS.FILTROS';
const qualquer = () => ({ value: '', label: t(`${FC}.QUALQUER`) });
const compras = () => ({
  chave: 'compras',
  rotuloCompleto: `${FC}.COMPRAS`,
  opcoes: [
    qualquer(),
    { value: COMPRAS.JA_COMPROU, label: t(`${FC}.JA_COMPROU`) },
    { value: COMPRAS.NUNCA, label: t(`${FC}.NUNCA_COMPROU`) },
    ...Object.entries(DIAS_DAS_COMPRAS).map(([value, dias]) => ({
      value,
      label: t(`${FC}.ULTIMOS`, { count: dias }),
    })),
  ],
});
const totalAcima = () => ({
  chave: 'totalAcima',
  rotuloCompleto: `${FC}.TOTAL`,
  opcoes: [
    qualquer(),
    ...TOTAIS_ACIMA.map(valor => ({
      value: String(valor),
      label: t(`${FC}.ACIMA`, {
        valor: formatarDinheiro(valor, 'BRL', idioma.value),
      }),
    })),
  ],
});
// #3100 — o cartão fidelidade (só em Pessoas): perto do prêmio ou completo.
const FF = 'FIDELIDADE.FILTRO';
const fidelidade = () => ({
  chave: 'fidelidade',
  rotuloCompleto: `${FF}.ROTULO`,
  opcoes: [
    { value: '', label: t(`${FF}.QUALQUER`) },
    { value: FIDELIDADE.PERTO, label: t(`${FF}.PERTO`) },
    { value: FIDELIDADE.COMPLETO, label: t(`${FF}.COMPLETO`) },
  ],
});
const temOQueEscolher = campo => campo.opcoes.length > 1;
const rotuloDo = campo =>
  t(campo.rotuloCompleto || `RELACIONAMENTOS.LISTA.FILTROS.${campo.rotulo}`);

const cidade = lista => ({
  chave: 'cidade',
  rotulo: 'CIDADE',
  opcoes: comTodas(lista ?? []),
});
const chegouEm = () => ({
  chave: 'chegouEm',
  rotulo: 'CHEGOU_EM',
  opcoes: periodos.value,
});

const campos = computed(() =>
  (props.deEmpresas
    ? [cidade(props.opcoes.cidades_das_empresas), chegouEm()]
    : [
        {
          chave: 'empresa',
          rotulo: 'EMPRESA',
          opcoes: comTodas(props.opcoes.empresas ?? []),
        },
        {
          chave: 'etiqueta',
          rotulo: 'ETIQUETA',
          opcoes: comTodas(props.opcoes.etiquetas ?? []),
        },
        cidade(props.opcoes.cidades),
        chegouEm(),
        compras(),
        ...(props.veValores ? [totalAcima()] : []),
        ...(props.comFidelidade ? [fidelidade()] : []),
      ]
  ).filter(temOQueEscolher)
);

const escolher = (chave, valor) => {
  rascunho.value = { ...rascunho.value, [chave]: valor };
};

const aoTeclar = evento => {
  if (evento.key === 'Escape') {
    evento.stopPropagation();
    emit('fechar');
    return;
  }
  prender(evento);
};
</script>

<template>
  <TeleportWithDirection to="body">
    <transition
      enter-active-class="transition-opacity duration-200 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="aberta"
        aria-hidden="true"
        class="fixed inset-0 z-40 bg-n-alpha-black1"
        @click="emit('fechar')"
      />
    </transition>
    <transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
      leave-active-class="transition duration-150 ease-in"
      leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
    >
      <div
        v-if="aberta"
        ref="raiz"
        data-relacionamentos="gaveta-filtros"
        role="dialog"
        aria-modal="true"
        :aria-labelledby="idDoTitulo"
        class="fixed inset-y-0 z-50 flex flex-col w-[26rem] max-w-full shadow-2xl bg-n-solid-1 ltr:right-0 rtl:left-0"
        @keydown="aoTeclar"
      >
        <header class="flex items-center justify-between gap-3 px-6 py-5">
          <h2
            :id="idDoTitulo"
            data-view-title
            tabindex="-1"
            class="m-0 text-lg font-semibold text-n-slate-12"
          >
            {{ t('RELACIONAMENTOS.LISTA.FILTROS.TITULO') }}
          </h2>
          <Button
            ghost
            slate
            class="size-11"
            icon="i-lucide-x"
            :aria-label="t('RELACIONAMENTOS.LISTA.FILTROS.FECHAR')"
            @click="emit('fechar')"
          />
        </header>
        <div
          class="flex flex-col flex-1 min-h-0 gap-5 px-6 pb-6 overflow-y-auto"
        >
          <div
            v-for="campo in campos"
            :key="campo.chave"
            class="flex flex-col gap-2"
          >
            <label
              :for="`${idBase}-${campo.chave}`"
              class="text-sm font-medium text-n-slate-12"
            >
              {{ rotuloDo(campo) }}
            </label>
            <ChoiceSelect
              :model-value="rascunho[campo.chave]"
              :options="campo.opcoes"
              :trigger-id="`${idBase}-${campo.chave}`"
              :aria-label="rotuloDo(campo)"
              @update:model-value="escolher(campo.chave, $event)"
            />
          </div>
        </div>
        <footer class="flex flex-col gap-3 px-6 py-5 border-t border-n-weak">
          <Button
            size="lg"
            :label="t('RELACIONAMENTOS.LISTA.FILTROS.VER_RESULTADO')"
            @click="emit('aplicar', { ...rascunho })"
          />
          <Button
            slate
            ghost
            size="lg"
            :label="t('RELACIONAMENTOS.LISTA.FILTROS.LIMPAR')"
            @click="emit('limpar')"
          />
        </footer>
      </div>
    </transition>
  </TeleportWithDirection>
</template>
