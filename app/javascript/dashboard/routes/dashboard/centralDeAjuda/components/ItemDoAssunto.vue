<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracaoCurta, temVideo } from '../helpers/assunto';

// Um artigo da lista do assunto: o item inteiro é o link para ele. O número no círculo segue a
// ordem da API; visto, vira check.
const props = defineProps({
  artigo: { type: Object, required: true },
  posicao: { type: Number, required: true },
  visto: { type: Boolean, default: false },
  // Primeiros passos já tem "Passo N —" no título: sem número no círculo.
  numerado: { type: Boolean, default: true },
  // Algum artigo da lista tem vídeo: quem não tem guarda o espaço, e os títulos ficam alinhados.
  espacoDaMiniatura: { type: Boolean, default: false },
});

const { t } = useI18n();

const rota = computed(() => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: props.artigo.ref },
}));
const duracao = computed(() => duracaoCurta(props.artigo.duracao));
const comVideo = computed(() => temVideo(props.artigo));
</script>

<template>
  <router-link
    :to="rota"
    class="flex min-h-11 items-start gap-3 px-4 py-4 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand sm:gap-4 sm:px-5"
  >
    <span
      class="mt-0.5 grid size-8 shrink-0 place-items-center rounded-full text-sm font-semibold"
      :class="
        visto
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'border border-n-weak bg-n-solid-1 text-n-slate-11'
      "
      aria-hidden="true"
    >
      <span v-if="visto" class="i-lucide-check size-4" />
      <template v-else-if="numerado">{{ posicao }}</template>
      <span v-else class="i-lucide-circle-small size-4" />
    </span>

    <!-- Vídeo sem a miniatura publicada ainda mostra que é vídeo, e quanto dura. -->
    <span
      v-if="comVideo"
      class="relative block aspect-[16/10] w-20 shrink-0 overflow-hidden rounded-lg border border-n-weak bg-n-slate-3 sm:w-40"
      aria-hidden="true"
    >
      <img
        v-if="artigo.poster"
        :src="artigo.poster"
        alt=""
        loading="lazy"
        class="block size-full object-cover"
      />
      <span v-else class="grid size-full place-items-center text-n-slate-10">
        <span class="i-lucide-circle-play size-6" />
      </span>
      <span
        v-if="duracao"
        class="absolute bottom-1 inline-flex items-center gap-1 rounded-md bg-n-slate-12/80 px-1.5 py-0.5 text-xs font-medium text-n-slate-1 ltr:right-1 rtl:left-1"
      >
        <span class="i-lucide-play size-3" />
        {{ duracao }}
      </span>
    </span>
    <span
      v-else-if="espacoDaMiniatura"
      class="block w-20 shrink-0 sm:w-40"
      aria-hidden="true"
    />

    <span class="flex min-w-0 flex-1 flex-col gap-1">
      <span class="break-words text-base font-medium text-n-slate-12">
        {{ artigo.titulo }}
      </span>
      <span
        v-if="artigo.descricao"
        class="break-words text-sm text-n-slate-11 max-sm:line-clamp-3"
      >
        {{ artigo.descricao }}
      </span>
      <span v-if="duracao" class="sr-only">
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VIDEO_DE', { duracao }) }}
      </span>
      <span
        v-if="visto"
        class="inline-flex items-center gap-1 text-sm font-medium text-n-teal-11"
      >
        <span class="i-lucide-circle-check size-4" aria-hidden="true" />
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VISTO') }}
      </span>
    </span>
  </router-link>
</template>
