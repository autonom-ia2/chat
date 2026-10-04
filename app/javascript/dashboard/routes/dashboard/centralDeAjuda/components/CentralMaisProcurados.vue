<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { MAIS_PROCURADOS, atalhosVisiveis } from '../helpers/atalhos';

// Os pedidos mais comuns, a um clique, logo abaixo da busca.
const props = defineProps({
  capitulos: { type: Array, required: true },
});

const { t } = useI18n();

const atalhos = computed(() =>
  atalhosVisiveis(MAIS_PROCURADOS, props.capitulos)
);
</script>

<template>
  <nav
    v-show="atalhos.length"
    class="flex flex-wrap items-center gap-2"
    :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.MAIS_PROCURADOS.TITULO')"
  >
    <template v-if="atalhos.length">
      <span class="text-sm font-medium text-n-slate-11">
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.MAIS_PROCURADOS.TITULO') }}
      </span>
      <router-link
        v-for="atalho in atalhos"
        :key="atalho.rotulo"
        :to="{ name: 'central_de_ajuda_artigo', params: { ref: atalho.ref } }"
        class="inline-flex min-h-11 items-center rounded-full border border-n-weak bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 hover:border-n-brand hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        {{ t(`HELP_CENTER.CENTRAL_DE_AJUDA.MAIS_PROCURADOS.${atalho.rotulo}`) }}
      </router-link>
    </template>
  </nav>
</template>
