<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { SINTOMAS, atalhosVisiveis } from '../helpers/atalhos';

// "Algo não funcionou?": o problema dito do jeito que a pessoa sente, levando ao artigo que resolve.
const props = defineProps({
  capitulos: { type: Array, required: true },
});

const { t } = useI18n();

const sintomas = computed(() => atalhosVisiveis(SINTOMAS, props.capitulos));
</script>

<template>
  <section
    v-if="sintomas.length"
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm lg:flex-[2]"
    aria-labelledby="central-sintomas"
  >
    <h2
      id="central-sintomas"
      class="mb-0 flex items-center gap-2 text-lg font-semibold text-n-slate-12"
    >
      <span
        class="i-lucide-circle-alert size-5 text-n-amber-11"
        aria-hidden="true"
      />
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.SINTOMAS.TITULO') }}
    </h2>
    <ul class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="sintoma in sintomas" :key="sintoma.rotulo">
        <router-link
          :to="{
            name: 'central_de_ajuda_artigo',
            params: { ref: sintoma.ref },
          }"
          class="flex min-h-11 items-center justify-between gap-3 rounded-xl px-3 py-2 text-base text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ t(`HELP_CENTER.CENTRAL_DE_AJUDA.SINTOMAS.${sintoma.rotulo}`) }}
          <span
            class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
        </router-link>
      </li>
    </ul>
  </section>
</template>
