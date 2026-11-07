<script setup>
import { computed, ref } from 'vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';

// #2414 F5 — o "+" entre dois passos abre este seletor: os passos do catálogo,
// por grupo. Só entra o que o motor roda (decisão da F5: nada de "em breve").
// Passo que pede uma flag da conta (`requer`) só entra com ela ligada.
const props = defineProps({
  catalogo: { type: Object, required: true },
  liberado: { type: Function, required: true },
  // G13 (#2670): o passo com `chave` (permissão) só entra para quem a tem.
  temChave: { type: Function, default: () => true },
});

const emit = defineEmits(['escolher', 'close']);

const painel = ref(null);

const grupos = computed(() =>
  props.catalogo.grupos
    .map(grupo => ({
      ...grupo,
      passos: props.catalogo.passos.filter(
        passo =>
          passo.grupo === grupo.chave &&
          (!passo.requer || props.liberado(passo.requer)) &&
          (!passo.chave || props.temChave(passo.chave))
      ),
    }))
    .filter(grupo => grupo.passos.length)
);

const chaveDo = passo => passo.nome || passo.tipo;

const open = () => painel.value?.open();
const close = () => painel.value?.close();

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="painel"
    :title="$t('AUTOMACAO_LIVRE.SELETOR.TITULO')"
    :description="$t('AUTOMACAO_LIVRE.SELETOR.TEXTO')"
    width="lg"
    @close="emit('close')"
  >
    <div data-seletor class="flex flex-col gap-6">
      <section
        v-for="grupo in grupos"
        :key="grupo.chave"
        :data-grupo="grupo.chave"
        class="flex flex-col gap-2"
      >
        <h4 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ $t(grupo.frase) }}
        </h4>
        <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
          <li v-for="passo in grupo.passos" :key="chaveDo(passo)">
            <button
              type="button"
              :data-tipo="chaveDo(passo)"
              class="flex items-center w-full gap-3 px-3 py-2 border text-start rounded-xl min-h-11 border-n-weak bg-n-solid-1 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="emit('escolher', passo)"
            >
              <span class="flex-1 text-[0.9375rem] text-n-slate-12">
                {{ $t(passo.frase) }}
              </span>
            </button>
          </li>
        </ul>
      </section>
    </div>
  </SidePanel>
</template>
