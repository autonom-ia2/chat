<script setup>
import { computed, nextTick, ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { useFocoPreso } from 'dashboard/components-next/NovaConversa/useFocoPreso';
import { FILTROS_VAZIOS } from '../../lista/filtros';
import { camposDoTopo } from '../../lista/camposDoTopo';
import { useIdioma } from '../../ficha/idioma';
import {
  catalogoDeInformacoes,
  condicoesProntas,
  erroDaCondicao,
} from '../../lista/informacoes';
import CondicoesDaGaveta from './CondicoesDaGaveta.vue';

// #2894 — "Mais filtros": gaveta à direita com foco preso (useFocoPreso, a
// mesma da gaveta de Nova conversa), Esc fecha e o foco volta ao botão que
// abriu. "Ver resultado" aplica; "Limpar" tira todos e fecha. Campo que só
// teria "Todas" (Empresa numa conta sem empresas) não aparece.
// #3078 — na aba Empresas (`deEmpresas`) a gaveta tem só os filtros que a
// empresa tem: a cidade (as cidades das empresas, `cidades_das_empresas`) e
// quando chegou.
// #3168 — com `comCondicoes` (aba Pessoas), a seção "Por outra informação"
// (CondicoesDaGaveta). Linha que escolheu a informação e não tem o valor
// segura a gaveta aberta e mostra o erro nela; linha sem informação não vai.
// Com `doGrupo` (o nome de um grupo guardado), a gaveta muda esse grupo: o
// rodapé vira "Guardar no grupo" (principal, `guardar`) e "Ver sem guardar"
// (`aplicar`).
const props = defineProps({
  aberta: { type: Boolean, default: false },
  deEmpresas: { type: Boolean, default: false },
  // #3097: sem ver valor de venda, sem o filtro do total comprado.
  veValores: { type: Boolean, default: false },
  filtros: { type: Object, default: () => ({ ...FILTROS_VAZIOS }) },
  opcoes: {
    type: Object,
    default: () => ({ empresas: [], etiquetas: [], cidades: [] }),
  },
  comCondicoes: { type: Boolean, default: false },
  // Os campos personalizados de contato da conta e se ela tem "Este contato é".
  definicoes: { type: Array, default: () => [] },
  comRelacao: { type: Boolean, default: false },
  doGrupo: { type: String, default: '' },
});
const emit = defineEmits(['fechar', 'aplicar', 'limpar', 'guardar']);

const { t } = useI18n();
const idDoTitulo = useId();
const idBase = useId();
const raiz = useTemplateRef('raiz');
const { prender } = useFocoPreso(
  raiz,
  computed(() => props.aberta)
);

const rascunho = ref({ ...FILTROS_VAZIOS });
const mostrarErros = ref(false);
watch(
  () => props.aberta,
  aberta => {
    if (!aberta) return;
    rascunho.value = { ...FILTROS_VAZIOS, ...props.filtros };
    mostrarErros.value = false;
  },
  { immediate: true }
);

// Os filtros de cima (lista/camposDoTopo.js). Campo que só teria "Todas" não
// aparece.
const idioma = useIdioma();
const temOQueEscolher = campo => campo.opcoes.length > 1;
const campos = computed(() =>
  camposDoTopo({
    t,
    idioma: idioma.value,
    opcoes: props.opcoes,
    deEmpresas: props.deEmpresas,
    veValores: props.veValores,
  }).filter(temOQueEscolher)
);

const escolher = (chave, valor) => {
  rascunho.value = { ...rascunho.value, [chave]: valor };
};

const informacoes = computed(() =>
  catalogoDeInformacoes({
    t,
    idioma: idioma.value,
    definicoes: props.definicoes,
    comRelacao: props.comRelacao,
    etiquetas: props.opcoes.etiquetas ?? [],
  })
);
const errosDasCondicoes = computed(() =>
  Object.fromEntries(
    rascunho.value.condicoes
      .map(condicao => [condicao.id, erroDaCondicao(condicao)])
      .filter(([, erro]) => erro)
  )
);
const errosNaTela = computed(() =>
  mostrarErros.value ? errosDasCondicoes.value : {}
);
// "Ver resultado" (ou "Guardar no grupo"): com valor faltando, a gaveta fica
// aberta e o foco vai para a primeira linha com erro.
const focarPrimeiroErro = async () => {
  await nextTick();
  raiz.value?.querySelector('[aria-invalid="true"]')?.focus();
};
const confirmar = evento => {
  if (props.comCondicoes && Object.keys(errosDasCondicoes.value).length) {
    mostrarErros.value = true;
    focarPrimeiroErro();
    return;
  }
  const filtros = {
    ...rascunho.value,
    condicoes: props.comCondicoes
      ? condicoesProntas(rascunho.value.condicoes)
      : [],
  };
  if (evento === 'guardar') emit('guardar', filtros);
  else emit('aplicar', filtros);
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
          <div class="flex flex-col min-w-0">
            <h2
              :id="idDoTitulo"
              data-view-title
              tabindex="-1"
              class="m-0 text-lg font-semibold text-n-slate-12"
            >
              {{ t('RELACIONAMENTOS.LISTA.FILTROS.TITULO') }}
            </h2>
            <p
              v-if="doGrupo"
              class="m-0 mt-1 text-sm break-words text-n-slate-11"
              data-relacionamentos="gaveta-do-grupo"
            >
              {{
                t('RELACIONAMENTOS.LISTA.MEUS_GRUPOS.MUDANDO', {
                  nome: doGrupo,
                })
              }}
            </p>
          </div>
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
              {{ campo.rotulo }}
            </label>
            <ChoiceSelect
              :model-value="rascunho[campo.chave]"
              :options="campo.opcoes"
              :trigger-id="`${idBase}-${campo.chave}`"
              :aria-label="campo.rotulo"
              @update:model-value="escolher(campo.chave, $event)"
            />
          </div>
          <CondicoesDaGaveta
            v-if="comCondicoes"
            :condicoes="rascunho.condicoes"
            :juntar="rascunho.juntar"
            :informacoes="informacoes"
            :erros="errosNaTela"
            @update:condicoes="escolher('condicoes', $event)"
            @update:juntar="escolher('juntar', $event)"
          />
        </div>
        <footer
          v-if="doGrupo"
          class="flex flex-col gap-3 px-6 py-5 border-t border-n-weak"
        >
          <Button
            size="lg"
            data-relacionamentos="guardar-no-grupo"
            :label="t('RELACIONAMENTOS.LISTA.MEUS_GRUPOS.GUARDAR_NO_GRUPO')"
            @click="confirmar('guardar')"
          />
          <Button
            slate
            ghost
            size="lg"
            :label="t('RELACIONAMENTOS.LISTA.MEUS_GRUPOS.VER_SEM_GUARDAR')"
            @click="confirmar('aplicar')"
          />
        </footer>
        <footer
          v-else
          class="flex flex-col gap-3 px-6 py-5 border-t border-n-weak"
        >
          <Button
            size="lg"
            :label="t('RELACIONAMENTOS.LISTA.FILTROS.VER_RESULTADO')"
            @click="confirmar('aplicar')"
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
