<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ItemDoAssunto from './ItemDoAssunto.vue';
import { temVideo } from '../helpers/assunto';

// Os artigos do assunto num bloco só, na ordem da API, com divisória entre eles.
const props = defineProps({
  artigos: { type: Array, required: true },
  foiVisto: { type: Function, required: true },
  numerado: { type: Boolean, default: true },
});

const { t } = useI18n();

const espacoDaMiniatura = computed(() => props.artigos.some(temVideo));
</script>

<template>
  <section class="flex flex-col gap-3" aria-labelledby="assunto-artigos">
    <h2 id="assunto-artigos" class="mb-0 text-lg font-semibold text-n-slate-12">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.LISTA') }}
    </h2>
    <ol
      class="m-0 list-none divide-y divide-n-weak overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 p-0"
    >
      <li v-for="(artigo, indice) in artigos" :key="artigo.id">
        <ItemDoAssunto
          :artigo="artigo"
          :posicao="indice + 1"
          :visto="foiVisto(artigo.id)"
          :numerado="numerado"
          :espaco-da-miniatura="espacoDaMiniatura"
        />
      </li>
    </ol>
  </section>
</template>
