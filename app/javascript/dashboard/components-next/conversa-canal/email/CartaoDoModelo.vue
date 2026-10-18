<script setup>
// Um modelo na janela "Modelo de e-mail" (#1786): a miniatura é o próprio e-mail,
// desenhado em escala (600 px de largura reduzidos ao cartão), sem clique nos links.
// Com miniatura salva em Campanhas, usa a imagem. A prévia é pedida uma vez por modelo.
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import { preencherModelo } from './modeloDeEmail';
import { previaDoModelo } from './previasDosModelos';

const props = defineProps({
  modelo: { type: Object, required: true },
});
defineEmits(['escolher']);

const LARGURA_DO_EMAIL = 600;

const area = useTemplateRef('area');
const { width } = useElementSize(area);
const escala = computed(() => (width.value || 200) / LARGURA_DO_EMAIL);
const html = ref('');
const falhou = ref(false);

onMounted(async () => {
  if (props.modelo.miniatura) return;
  try {
    const montado = await previaDoModelo(props.modelo.id);
    html.value = `<style>a{pointer-events:none}body{margin:0}</style>${preencherModelo(montado, {})}`;
  } catch {
    falhou.value = true;
  }
});
</script>

<template>
  <button
    type="button"
    class="group flex flex-col w-full overflow-hidden rounded-2xl border border-n-weak bg-n-surface-1 text-start transition-all duration-200 hover:-translate-y-0.5 hover:border-n-slate-7 hover:shadow-[0_2px_6px_rgba(0,0,0,0.08),0_12px_28px_rgba(0,0,0,0.10)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
    :data-modelo-de-email="modelo.id"
    @click="$emit('escolher', modelo)"
  >
    <span
      ref="area"
      class="relative block aspect-[4/5] w-full overflow-hidden bg-n-alpha-1"
    >
      <img
        v-if="modelo.miniatura"
        :src="modelo.miniatura"
        :alt="modelo.nome"
        loading="lazy"
        class="size-full object-cover object-top"
      />
      <iframe
        v-else-if="html"
        :srcdoc="html"
        sandbox=""
        tabindex="-1"
        aria-hidden="true"
        class="absolute top-0 start-0 h-[1100px] border-0 pointer-events-none origin-top-left bg-white"
        :style="{ width: `${LARGURA_DO_EMAIL}px`, transform: `scale(${escala})` }"
      />
      <span
        v-else
        class="grid place-content-center size-full text-n-teal-10"
      >
        <Icon
          :icon="falhou ? 'i-ph-layout-fill' : 'i-lucide-loader-circle'"
          class="size-8"
          :class="{ 'animate-spin text-n-slate-9': !falhou }"
        />
      </span>
      <span
        class="absolute inset-x-0 bottom-0 h-12 bg-gradient-to-t from-n-surface-1 to-transparent"
        aria-hidden="true"
      />
      <span
        class="absolute inset-0 grid place-content-center opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 transition-opacity bg-n-alpha-black1"
        aria-hidden="true"
      >
        <span
          class="inline-flex items-center gap-1.5 h-9 px-4 rounded-full bg-n-brand text-white text-sm font-medium shadow-lg"
        >
          <Icon icon="i-lucide-check" class="size-4" />
          {{ $t('CONVERSA_CANAL.EMAIL.USAR_ESTE') }}
        </span>
      </span>
    </span>
    <span class="flex flex-col gap-1 px-3.5 py-3 border-t border-n-weak">
      <span
        class="line-clamp-2 text-sm font-medium leading-5 text-n-slate-12"
        :title="modelo.nome"
      >
        {{ modelo.nome }}
      </span>
      <span
        v-if="modelo.categoria"
        class="self-start inline-flex items-center h-5 px-1.5 rounded text-[11px] font-medium bg-n-alpha-2 text-n-slate-11"
      >
        {{ modelo.categoria }}
      </span>
    </span>
  </button>
</template>
