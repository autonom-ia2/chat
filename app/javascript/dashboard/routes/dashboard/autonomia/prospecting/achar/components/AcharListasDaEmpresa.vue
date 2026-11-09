<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { useListasDaEmpresa } from '../composables/useListasDaEmpresa';

// #2775 — F6, na gaveta da empresa: em quais listas ela está, com "Tirar" e,
// depois de tirar, "Desfazer". Só para quem pode guardar listas (a mesma
// permissão do Guardar lista); sem lista nenhuma, nada aparece.
const props = defineProps({
  empresaId: { type: [Number, String], required: true },
});

const NS = 'PROSPECTING_ACHAR.LISTAS_DA_EMPRESA';
const { fonte, permissoes } = useAcharTela();
const podeLista = computed(() => permissoes.value.lista === true);
const { listas, saida, ocupado, erro, tirar, desfazer } = useListasDaEmpresa({
  fonte,
  empresaId: () => props.empresaId,
  podeLista,
});
</script>

<template>
  <section
    v-if="podeLista && (listas.length || saida)"
    class="flex flex-col gap-2"
    data-listas-da-empresa
  >
    <div
      v-for="lista in listas"
      :key="lista.id"
      class="flex flex-wrap items-center gap-2 px-4 py-2 border border-solid rounded-2xl border-n-weak"
      data-lista-da-empresa
    >
      <span class="i-lucide-list size-4 text-n-teal-11" aria-hidden="true" />
      <span class="flex-1 min-w-0 text-base break-words text-n-slate-12">
        {{ $t(`${NS}.ESTA_NA`, { nome: lista.nome }) }}
      </span>
      <span
        v-if="lista.enviada"
        class="px-3 py-1 text-sm rounded-full bg-n-slate-3 text-n-slate-11"
      >
        {{ $t(`${NS}.ENVIADA`) }}
      </span>
      <Button
        v-else
        :label="$t(`${NS}.TIRAR`)"
        :disabled="ocupado"
        slate
        faded
        size="sm"
        class="!min-h-11 !rounded-xl"
        data-tirar-da-lista
        @click="tirar(lista)"
      />
    </div>
    <div
      v-if="saida"
      role="status"
      class="flex flex-wrap items-center gap-2 px-4 py-2 border border-solid rounded-2xl border-n-teal-6 bg-n-teal-2"
      data-saiu-da-lista
    >
      <span class="flex-1 min-w-0 text-base break-words text-n-slate-12">
        {{ $t(`${NS}.SAIU`, { nome: saida.lista.nome }) }}
      </span>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.DESFAZER')"
        :disabled="ocupado"
        variant="link"
        class="!min-h-11 !px-0"
        data-desfazer-tirar
        @click="desfazer"
      />
    </div>
    <p v-if="erro" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ $t(`${NS}.ERRO_${erro}`) }}
    </p>
  </section>
</template>
