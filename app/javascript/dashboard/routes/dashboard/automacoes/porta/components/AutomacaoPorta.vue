<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CartaoDeCatalogo from 'dashboard/components-next/cartao-de-catalogo/CartaoDeCatalogo.vue';
import ModeloDetalhe from './ModeloDetalhe.vue';
import { usePorta } from '../usePorta';
import { useIrAoGuia } from '../useIrAoGuia';
import {
  GRUPOS,
  camadaDoDestaque,
  emDestaque,
  modelosDaConta,
  tomDoGrupo,
} from '../modelos';

// #2889 — os modelos prontos da porta de Automações, com os do segmento da conta em destaque. A pergunta do topo
// (herói) fica na lista, acima das automações da pessoa; os modelos vêm depois delas. Tocar num modelo abre o
// detalhe; "Usar este modelo" leva o pedido ao Guia, que pergunta só o que é da conta. Nada liga sem a pessoa mandar.
defineProps({
  desabilitado: { type: Boolean, default: false },
});

const { t } = useI18n();
const { usarModelo: usar } = useIrAoGuia();

const { camadas } = usePorta();

const NS = 'AUTOMACAO_MODELOS';
const comTexto = modelo => ({
  ...modelo,
  titulo: t(`${NS}.ITENS.${modelo.id}.TITULO`),
  texto: t(`${NS}.ITENS.${modelo.id}.TEXTO`),
  tom: tomDoGrupo(modelo.grupo),
});
const modelos = computed(() => modelosDaConta(camadas.value).map(comTexto));

const grupo = ref('TODOS');
const gruposComModelo = computed(() =>
  GRUPOS.filter(item => modelos.value.some(m => m.grupo === item.id))
);
const destaque = computed(() =>
  grupo.value === 'TODOS' ? emDestaque(modelos.value, camadas.value) : []
);
// Em "Todos", o modelo que já está no destaque não se repete no grupo dele.
const foraDoDestaque = modelo =>
  !destaque.value.some(item => item.id === modelo.id);
const visiveis = computed(() =>
  gruposComModelo.value
    .filter(item => grupo.value === 'TODOS' || item.id === grupo.value)
    .map(item => ({
      ...item,
      modelos: modelos.value.filter(
        m => m.grupo === item.id && foraDoDestaque(m)
      ),
    }))
    .filter(item => item.modelos.length)
);
const tituloDoDestaque = computed(() =>
  camadaDoDestaque(camadas.value)
    ? t(`${NS}.DESTAQUE_RAMO`)
    : t(`${NS}.DESTAQUE_GERAL`)
);

const seloDe = modelo =>
  modelo.ia ? { texto: t(`${NS}.USA_IA`), icone: 'i-lucide-sparkles' } : null;

const aberto = ref(null);
const detalhe = ref(null);
const abrir = modelo => {
  aberto.value = modelo;
  detalhe.value?.open();
};
</script>

<template>
  <div data-porta class="flex flex-col gap-8">
    <section
      data-modelos
      aria-labelledby="modelos-titulo"
      class="flex flex-col gap-5"
    >
      <div>
        <h2
          id="modelos-titulo"
          class="mb-0 text-2xl font-semibold tracking-tight text-n-slate-12"
        >
          {{ $t(`${NS}.TITULO`) }}
        </h2>
        <p class="mb-0 mt-1.5 text-base text-n-slate-11">
          {{ $t(`${NS}.TEXTO`) }}
        </p>
      </div>

      <div
        role="group"
        :aria-label="$t(`${NS}.GRUPOS_ARIA`)"
        class="flex gap-2 pb-1 max-sm:overflow-x-auto sm:flex-wrap"
      >
        <button
          v-for="item in [{ id: 'TODOS' }, ...gruposComModelo]"
          :key="item.id"
          type="button"
          :data-grupo="item.id"
          :aria-pressed="grupo === item.id"
          class="px-4 text-sm font-medium transition border rounded-full shrink-0 min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
          :class="
            grupo === item.id
              ? 'bg-n-blue-10 border-n-blue-10 text-white'
              : 'bg-n-slate-2 border-n-slate-6 text-n-slate-12 hover:border-n-blue-6'
          "
          @click="grupo = item.id"
        >
          {{
            item.id === 'TODOS'
              ? $t(`${NS}.TODOS`)
              : $t(`${NS}.GRUPOS.${item.id}`)
          }}
        </button>
      </div>

      <div
        v-if="destaque.length"
        data-destaque
        class="flex flex-col gap-4 p-5 sm:-mx-5 rounded-3xl bg-n-blue-2 dark:bg-n-alpha-1"
      >
        <h3
          class="flex items-center gap-2 mb-0 text-lg font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-sparkles size-5 text-n-blue-11"
            aria-hidden="true"
          />
          {{ tituloDoDestaque }}
        </h3>
        <ul class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3">
          <li v-for="modelo in destaque" :key="modelo.id" class="min-w-0">
            <CartaoDeCatalogo
              :data-modelo="modelo.id"
              :titulo="modelo.titulo"
              :texto="modelo.texto"
              :icone="modelo.icone"
              :tom="modelo.tom"
              :selo="seloDe(modelo)"
              destaque
              @abrir="abrir(modelo)"
            />
          </li>
        </ul>
      </div>

      <section
        v-for="item in visiveis"
        :key="item.id"
        :data-grupo-lista="item.id"
        class="flex flex-col gap-3"
      >
        <h3
          class="flex items-center gap-2 mb-0 text-lg font-semibold text-n-slate-12"
        >
          <span :class="item.icone" class="size-5" aria-hidden="true" />
          {{ $t(`${NS}.GRUPOS.${item.id}`) }}
        </h3>
        <ul class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3">
          <li v-for="modelo in item.modelos" :key="modelo.id" class="min-w-0">
            <CartaoDeCatalogo
              :data-modelo="modelo.id"
              :titulo="modelo.titulo"
              :texto="modelo.texto"
              :icone="modelo.icone"
              :tom="modelo.tom"
              :selo="seloDe(modelo)"
              @abrir="abrir(modelo)"
            />
          </li>
        </ul>
      </section>
    </section>

    <ModeloDetalhe
      ref="detalhe"
      :modelo="aberto"
      :desabilitado="desabilitado"
      @usar="usar"
    />
  </div>
</template>
