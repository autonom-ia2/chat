<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { duracaoCurta, temVideo } from '../helpers/assunto';

// O artigo que o Jev escolheu como resposta ao que a pessoa escreveu (#977). Aparece acima da
// lista por palavras, com destaque, só quando a certeza passa do limiar. `secundaria` é a alternativa
// (#985): o outro artigo que também ajuda, com menos peso visual que a resposta.
const props = defineProps({
  artigo: { type: Object, required: true },
  secundaria: { type: Boolean, default: false },
});

const { t } = useI18n();

const rota = computed(() => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: props.artigo.ref },
}));
const comVideo = computed(() => temVideo(props.artigo));
const duracao = computed(() => duracaoCurta(props.artigo.duracao));
</script>

<template>
  <router-link
    :to="rota"
    class="flex min-h-11 flex-col gap-2 rounded-xl bg-n-solid-1 px-5 py-4 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
    :class="
      secundaria
        ? 'border border-n-brand/40'
        : 'border-2 border-n-brand shadow-sm'
    "
  >
    <span class="flex flex-wrap items-center gap-2">
      <span
        v-if="secundaria"
        class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs font-semibold text-n-slate-11"
      >
        <span class="i-lucide-lightbulb size-3.5" aria-hidden="true" />
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.TAMBEM_AJUDA') }}
      </span>
      <span
        v-else
        class="inline-flex items-center gap-1 rounded-full bg-n-brand/10 px-2.5 py-0.5 text-xs font-semibold text-n-blue-11"
      >
        <span class="i-lucide-sparkles size-3.5" aria-hidden="true" />
        {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.MELHOR_RESPOSTA') }}
      </span>
      <span
        v-if="comVideo"
        class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs font-medium text-n-slate-11"
        aria-hidden="true"
      >
        <span class="i-lucide-play size-3" />
        {{ duracao || t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.COM_VIDEO') }}
      </span>
    </span>
    <span class="break-words text-lg font-medium text-n-slate-12">
      {{ artigo.titulo }}
    </span>
    <span v-if="artigo.descricao" class="break-words text-base text-n-slate-11">
      {{ artigo.descricao }}
    </span>
    <span v-if="artigo.capitulo" class="text-sm text-n-slate-10">
      {{ artigo.capitulo }}
    </span>
    <!-- O selo é visual; o leitor de tela ouve a frase inteira. -->
    <span v-if="comVideo" class="sr-only">
      {{
        duracao
          ? t('HELP_CENTER.CENTRAL_DE_AJUDA.ASSUNTO.VIDEO_DE', { duracao })
          : t('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.COM_VIDEO')
      }}
    </span>
  </router-link>
</template>
