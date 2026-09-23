<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { watchDebounced } from '@vueuse/core';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  guiaDisponivel: { type: Boolean, default: false },
});
const emit = defineEmits(['perguntar']);
// Verdadeiro enquanto há texto na busca: a página esconde os assuntos para a pessoa olhar só os resultados.
const ativa = defineModel('ativa', { type: Boolean, default: false });

const ESPERA_MS = 300;

const { t } = useI18n();
const router = useRouter();

const termo = ref('');
const resultados = ref([]);
const buscando = ref(false);
const erro = ref(false);
let ultimaBusca = 0;

const temTermo = computed(() => termo.value.trim().length > 0);
watch(temTermo, valor => {
  ativa.value = valor;
});

const buscar = async texto => {
  ultimaBusca += 1;
  const pedido = ultimaBusca;
  if (!texto.trim()) {
    resultados.value = [];
    erro.value = false;
    return;
  }
  buscando.value = true;
  try {
    const { data } = await CentralDeAjudaAPI.buscar(texto);
    if (pedido !== ultimaBusca) return; // chegou depois de uma busca mais nova
    resultados.value = data.resultados || [];
    erro.value = false;
  } catch {
    if (pedido === ultimaBusca) erro.value = true;
  } finally {
    if (pedido === ultimaBusca) buscando.value = false;
  }
};

watchDebounced(termo, buscar, { debounce: ESPERA_MS });

const abrir = artigo =>
  router.push({ name: 'central_de_ajuda_artigo', params: { ref: artigo.ref } });

const abrirPrimeiro = () => {
  if (resultados.value.length) abrir(resultados.value[0]);
};

const limpar = () => {
  termo.value = '';
  resultados.value = [];
};
</script>

<template>
  <div role="search" class="flex flex-col gap-3">
    <label for="busca-central" class="sr-only">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ROTULO') }}
    </label>
    <div class="relative">
      <span
        class="i-lucide-search absolute top-1/2 -translate-y-1/2 ltr:left-4 rtl:right-4 size-6 text-n-slate-10 pointer-events-none"
        aria-hidden="true"
      />
      <input
        id="busca-central"
        v-model="termo"
        type="text"
        inputmode="search"
        enterkeyhint="search"
        autocomplete="off"
        class="reset-base w-full h-16 ltr:pl-14 rtl:pr-14 ltr:pr-14 rtl:pl-14 text-lg rounded-2xl border border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 outline-none focus:border-n-brand focus:outline focus:outline-2 focus:outline-n-brand"
        :placeholder="t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PLACEHOLDER')"
        aria-describedby="busca-central-dica"
        @keydown.enter.prevent="abrirPrimeiro"
      />
      <button
        v-if="temTermo"
        type="button"
        class="absolute top-1/2 -translate-y-1/2 ltr:right-2 rtl:left-2 size-11 grid place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.LIMPAR')"
        @click="limpar"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>

    <p
      v-if="!temTermo"
      id="busca-central-dica"
      class="mb-0 -mt-1 ltr:pl-1 rtl:pr-1 text-sm text-n-slate-11"
    >
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.DICA') }}
    </p>

    <p class="sr-only" aria-live="polite">
      <template v-if="temTermo && !buscando">
        {{
          t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.RESULTADOS', resultados.length)
        }}
      </template>
    </p>

    <p v-if="temTermo && erro" class="mb-0 text-base text-n-ruby-11">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ERRO') }}
    </p>

    <ul
      v-else-if="temTermo && resultados.length"
      class="m-0 p-0 list-none flex flex-col gap-2"
    >
      <li v-for="artigo in resultados" :key="artigo.ref">
        <router-link
          :to="{ name: 'central_de_ajuda_artigo', params: { ref: artigo.ref } }"
          class="flex flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-1 px-5 py-4 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          <span class="text-lg font-medium text-n-slate-12">
            {{ artigo.titulo }}
          </span>
          <span class="text-base text-n-slate-11">{{ artigo.descricao }}</span>
          <span class="text-sm text-n-slate-10">{{ artigo.capitulo }}</span>
        </router-link>
      </li>
    </ul>

    <div
      v-else-if="temTermo && !buscando"
      class="flex flex-wrap items-center gap-3 rounded-xl bg-n-alpha-1 px-5 py-4"
    >
      <p class="mb-0 text-base text-n-slate-11">
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.NADA') }}
      </p>
      <Button
        v-if="guiaDisponivel"
        size="lg"
        color="blue"
        variant="faded"
        icon="i-lucide-life-buoy"
        class="min-h-11"
        :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PERGUNTE')"
        @click="emit('perguntar')"
      />
    </div>
  </div>
</template>
