<script setup>
// #2996 — a linha de etiquetas do card da lista. Só entram as etiquetas que a conta marcou
// para aparecer na lista ("Exibir etiqueta na lista de conversas"); sem nenhuma, a linha
// fica escondida (v-show: a raiz não pode ter v-if). Até 2 à vista; o "+N" mostra a lista
// completa, com as cores. Fica fora do <button> do card (botão dentro de botão não é HTML válido).
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';

const props = defineProps({
  titulos: { type: Array, default: () => [] },
});

const VISIVEIS = 2;

const etiquetasDaConta = useMapGetter('labels/getLabels');
const { nomeDe } = useNomeDaEtiqueta();
const aberta = ref(false);

// Pelo conteúdo, não pela referência: o mesmo chat reemitido não recolhe a lista aberta.
watch(
  () => props.titulos.join('\n'),
  () => {
    aberta.value = false;
  }
);

const etiquetas = computed(() =>
  (etiquetasDaConta.value || [])
    .filter(
      etiqueta =>
        etiqueta.show_on_conversation_list &&
        props.titulos.includes(etiqueta.title)
    )
    .map(etiqueta => ({ ...etiqueta, nome: nomeDe(etiqueta.title) }))
    .sort((a, b) => a.nome.localeCompare(b.nome))
);
const naTela = computed(() =>
  aberta.value ? etiquetas.value : etiquetas.value.slice(0, VISIVEIS)
);
const escondidas = computed(() =>
  Math.max(etiquetas.value.length - VISIVEIS, 0)
);
</script>

<template>
  <ul
    v-show="etiquetas.length"
    class="flex flex-wrap items-center min-w-0 gap-1 p-0 m-0 list-none"
    :aria-label="$t('LISTA_DE_CONVERSAS.ETIQUETAS.ARIA')"
    data-etiquetas
  >
    <li
      v-for="etiqueta in naTela"
      :key="etiqueta.id"
      class="flex items-center min-w-0 gap-1 px-1.5 text-xs leading-5 rounded-md bg-n-alpha-2 text-n-slate-12 max-w-[10rem]"
      :title="etiqueta.nome"
      data-etiqueta
    >
      <span
        class="flex-shrink-0 rounded-sm size-2"
        :style="{ backgroundColor: etiqueta.color }"
      />
      <span class="truncate">{{ etiqueta.nome }}</span>
    </li>
    <li v-if="escondidas">
      <button
        type="button"
        class="flex items-center justify-center px-2 text-xs font-semibold rounded-md cursor-pointer min-h-6 min-w-6 bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="
          aberta
            ? undefined
            : $t(
                'LISTA_DE_CONVERSAS.ETIQUETAS.VER_TODAS',
                { n: escondidas },
                escondidas
              )
        "
        :aria-expanded="aberta ? 'true' : 'false'"
        data-mais-etiquetas
        @click.stop="aberta = !aberta"
      >
        {{
          aberta
            ? $t('LISTA_DE_CONVERSAS.ETIQUETAS.MENOS')
            : $t('LISTA_DE_CONVERSAS.ETIQUETAS.MAIS', { n: escondidas })
        }}
      </button>
    </li>
  </ul>
</template>
