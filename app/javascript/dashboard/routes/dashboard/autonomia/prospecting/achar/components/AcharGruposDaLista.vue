<script setup>
import { nextTick, watch } from 'vue';
import AcharEmpresaCartao from './AcharEmpresaCartao.vue';
import AcharGrupo from './AcharGrupo.vue';

// #2692 — os grupos da lista (v4, T1): o destaque "Chame primeiro" (rodada 2:
// fora de "Boa chance", com borda verde-água), os grupos por chance e, no fim,
// "Ficam de fora". Saiu de AcharConfiraPage.vue para a página caber no limite.
const props = defineProps({
  primeiro: { type: Object, default: null },
  grupos: { type: Array, required: true },
  deFora: { type: Array, required: true },
  tiradas: { type: Array, default: () => [] },
  naoVai: { type: Set, required: true },
  leitura: { type: Boolean, default: false },
  pesquisaLigada: { type: Boolean, default: true },
  whatsappLigado: { type: Boolean, default: true },
  comecaFechado: { type: Function, required: true },
  // Grupo que já abre na tela (estados da demonstração com os grupos de baixo).
  rolarAte: { type: String, default: null },
  // Empresa destacada pelo mapa (pino clicado) ou pelo clique no cartão.
  destacada: { type: [Number, String], default: null },
});
const emit = defineEmits(['abrir', 'alternar', 'tirar']);

const NS = 'PROSPECTING_ACHAR.CONFIRA';

watch(
  () => [props.rolarAte, props.grupos.length],
  async ([chave]) => {
    if (!chave) return;
    await nextTick();
    document
      .querySelector(`[data-grupo="${chave}"]`)
      ?.scrollIntoView({ block: 'start' });
  },
  { immediate: true }
);

// Pino clicado: a lista rola até o cartão, que fica destacado.
watch(
  () => props.destacada,
  async id => {
    if (id == null) return;
    await nextTick();
    document
      .querySelector(`[data-empresa="${id}"]`)
      ?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }
);
</script>

<template>
  <p
    v-if="!leitura"
    class="m-0 -mb-2 text-sm text-n-slate-11 md:hidden"
    data-desligue
  >
    {{ $t(`${NS}.DESLIGUE`) }}
  </p>
  <section
    v-if="primeiro"
    class="flex flex-col px-3 pt-3 border-2 md:px-4 rounded-2xl border-n-teal-7 bg-n-teal-2"
    data-chame-primeiro
  >
    <h2
      class="flex items-center gap-2 m-0 text-base font-semibold text-n-teal-11"
    >
      <span class="i-lucide-star size-4" aria-hidden="true" />
      {{ $t(`${NS}.GRUPOS.PRIMEIRO`) }}
    </h2>
    <ul class="p-0 m-0 list-none">
      <AcharEmpresaCartao
        :empresa="primeiro"
        :leitura="leitura"
        :destacada="destacada === primeiro.id"
        :vai="!naoVai.has(primeiro.id)"
        :pesquisa-ligada="pesquisaLigada"
        :whatsapp-ligado="whatsappLigado"
        @abrir="emit('abrir', primeiro)"
        @alternar="emit('alternar', primeiro)"
      />
    </ul>
  </section>

  <AcharGrupo
    v-for="grupo in grupos"
    :key="grupo.chave"
    :chave="grupo.chave"
    :titulo="
      $t(`${NS}.GRUPOS.${grupo.chave.toUpperCase()}`, {
        n: grupo.empresas.length,
      })
    "
    :comeca-fechado="comecaFechado(grupo.chave)"
    :pode-tirar="grupo.chave === 'pouca' && !leitura"
    @tirar="emit('tirar')"
  >
    <AcharEmpresaCartao
      v-for="empresa in grupo.empresas"
      :key="empresa.id"
      :empresa="empresa"
      :leitura="leitura"
      :destacada="destacada === empresa.id"
      :vai="!naoVai.has(empresa.id)"
      :pesquisa-ligada="pesquisaLigada"
      :whatsapp-ligado="whatsappLigado"
      @abrir="emit('abrir', empresa)"
      @alternar="emit('alternar', empresa)"
    />
  </AcharGrupo>

  <AcharGrupo
    v-if="deFora.length"
    chave="fora"
    :titulo="$t(`${NS}.GRUPOS.FORA`, { n: deFora.length })"
    :comeca-fechado="comecaFechado('fora')"
  >
    <AcharEmpresaCartao
      v-for="empresa in deFora"
      :key="empresa.id"
      :empresa="empresa"
      leitura
      :destacada="destacada === empresa.id"
      @abrir="emit('abrir', empresa)"
    />
  </AcharGrupo>

  <AcharGrupo
    v-if="tiradas.length"
    chave="tiradas"
    :titulo="$t(`${NS}.GRUPOS.TIRADAS`, { n: tiradas.length })"
    :comeca-fechado="comecaFechado('tiradas')"
  >
    <AcharEmpresaCartao
      v-for="empresa in tiradas"
      :key="empresa.id"
      :empresa="empresa"
      leitura
      :destacada="destacada === empresa.id"
      @abrir="emit('abrir', empresa)"
    />
  </AcharGrupo>
</template>
