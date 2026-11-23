<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntersectionObserver } from '@vueuse/core';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';

// #3113 — um arquivo da ficha: a miniatura em cima, o nome e quando embaixo. Tocar abre o arquivo numa aba nova;
// o vídeo toca ali mesmo (o servidor entrega vídeo como download, e o player da página toca assim mesmo).
// Miniatura: a foto ou a 1ª página do PDF (`miniatura`, do servidor); o vídeo, o primeiro quadro do próprio vídeo;
// o resto (áudio, planilha, PDF sem prévia, imagem que não carregou), o ícone do tipo com a extensão.
const props = defineProps({
  // { id, nome, tipo, quando, url, miniatura }
  arquivo: { type: Object, required: true },
  agora: { type: Number, required: true },
});

const ICONES = {
  imagem: 'i-lucide-image',
  documento: 'i-lucide-file-text',
  planilha: 'i-lucide-file-spreadsheet',
  audio: 'i-lucide-mic',
  video: 'i-lucide-video',
};
const FUNDOS = {
  imagem: 'bg-n-teal-3 text-n-teal-11',
  documento: 'bg-n-blue-3 text-n-blue-11',
  planilha: 'bg-n-teal-3 text-n-teal-11',
  audio: 'bg-n-amber-3 text-n-amber-11',
  video: 'bg-n-ruby-3 text-n-ruby-11',
};
const PLANILHAS = ['XLSX', 'XLS', 'CSV', 'ODS'];
// "planilha.xlsx" → "XLSX". Nome sem ponto ou extensão longa demais: sem selo.
const MAIOR_EXTENSAO = 4;

const { t } = useI18n();
const idioma = useIdioma();
const miniaturaFalhou = ref(false);
// O vídeo que não carrega ou não toca (formato, endereço vencido) vira o cartão do tipo, que abre numa aba nova.
const videoFalhou = ref(false);
const tocando = ref(false);
const video = ref(null);
const raiz = ref(null);
const apareceu = ref(false);

// O vídeo só pede o primeiro quadro quando o cartão chega perto da tela: com "Ver todos", até 50 cartões abrem de
// uma vez. Sem IntersectionObserver (navegador antigo), pede logo.
const { isSupported, stop: pararDeObservar } = useIntersectionObserver(
  raiz,
  ([entrada]) => {
    if (!entrada?.isIntersecting) return;
    apareceu.value = true;
    pararDeObservar();
  },
  { rootMargin: '200px' }
);
if (!isSupported.value) apareceu.value = true;

const partesDoNome = computed(() => {
  const partes = props.arquivo.nome.split('.');
  const ultima = partes.length > 1 ? partes.pop() : '';
  return ultima.length <= MAIOR_EXTENSAO
    ? { base: partes.join('.'), extensao: ultima.toUpperCase() }
    : { base: props.arquivo.nome, extensao: '' };
});
// O selo diz o tipo; a foto não leva selo.
const selo = computed(() =>
  props.arquivo.tipo === 'imagem' ? '' : partesDoNome.value.extensao
);
const nomeVisivel = computed(() =>
  selo.value ? partesDoNome.value.base : props.arquivo.nome
);
const aparencia = computed(() =>
  PLANILHAS.includes(selo.value) ? 'planilha' : props.arquivo.tipo
);
const comMiniatura = computed(
  () => Boolean(props.arquivo.miniatura) && !miniaturaFalhou.value
);
const ehVideo = computed(
  () =>
    !comMiniatura.value &&
    !videoFalhou.value &&
    props.arquivo.tipo === 'video' &&
    Boolean(props.arquivo.url)
);
const quadro = computed(() => {
  if (tocando.value) return props.arquivo.url;
  return apareceu.value ? `${props.arquivo.url}#t=0.1` : undefined;
});
const tipo = computed(() =>
  t(`RELACIONAMENTOS_FICHA.ARQUIVOS.TIPO.${props.arquivo.tipo}`)
);
const quando = computed(() =>
  quandoRelativo(props.arquivo.quando, props.agora, idioma.value)
);

// O vídeo é <button>, e botão não estica sozinho: sem w-full, um nome longo sem espaço alarga o cartão por cima dos outros.
const elemento = computed(() => {
  if (!props.arquivo.url || tocando.value) return 'div';
  return ehVideo.value ? 'button' : 'a';
});
const atributos = computed(() => {
  const valores = {
    nome: props.arquivo.nome,
    tipo: tipo.value,
    quando: quando.value,
  };
  if (elemento.value === 'a')
    return {
      href: props.arquivo.url,
      target: '_blank',
      rel: 'noopener noreferrer',
      'aria-label': t('RELACIONAMENTOS_FICHA.ARQUIVOS.ABRIR', valores),
    };
  if (elemento.value === 'button')
    return {
      type: 'button',
      'aria-label': t('RELACIONAMENTOS_FICHA.ARQUIVOS.TOCAR', valores),
    };
  return {};
});

const falhouAoTocar = () => {
  tocando.value = false;
  videoFalhou.value = true;
};

// O botão vira o player: o foco vai para ele, para quem usa teclado não cair no topo da página.
const tocar = async () => {
  if (!ehVideo.value || tocando.value) return;
  tocando.value = true;
  await nextTick();
  video.value?.focus?.();
  try {
    await video.value?.play?.();
  } catch (erro) {
    // AbortError: a pessoa pausou ou trocou de vídeo antes de começar; não é falha.
    if (erro?.name !== 'AbortError') falhouAoTocar();
  }
};
</script>

<template>
  <component
    :is="elemento"
    ref="raiz"
    v-bind="atributos"
    data-relacionamentos="arquivo"
    class="flex flex-col w-full min-w-0 gap-2 p-1 -m-1 text-left no-underline group rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="tocar"
  >
    <span
      class="relative block w-full overflow-hidden border aspect-[4/3] rounded-xl border-n-weak"
      :class="comMiniatura || ehVideo ? 'bg-n-alpha-2' : FUNDOS[aparencia]"
    >
      <img
        v-if="comMiniatura"
        :src="arquivo.miniatura"
        alt=""
        loading="lazy"
        class="object-cover object-top transition-transform duration-200 size-full motion-safe:group-hover:scale-105"
        @error="miniaturaFalhou = true"
      />
      <video
        v-else-if="ehVideo"
        ref="video"
        :src="quadro"
        preload="metadata"
        playsinline
        :muted="!tocando"
        :controls="tocando"
        :tabindex="tocando ? 0 : -1"
        :aria-hidden="tocando ? undefined : 'true'"
        class="size-full"
        :class="
          tocando
            ? 'object-contain bg-n-slate-12'
            : 'object-cover pointer-events-none'
        "
        @error="falhouAoTocar"
      />
      <span
        v-else
        class="flex flex-col items-center justify-center gap-2 size-full"
      >
        <span class="size-9" :class="ICONES[aparencia]" />
      </span>
      <span
        v-if="ehVideo && !tocando"
        class="absolute inset-0 flex items-center justify-center"
        aria-hidden="true"
      >
        <span
          class="flex items-center justify-center rounded-full shadow size-11 bg-n-solid-1/90 text-n-slate-12"
        >
          <span class="ml-0.5 size-5 i-lucide-play" />
        </span>
      </span>
      <span
        v-if="selo && !tocando"
        class="absolute px-2 py-0.5 text-xs font-semibold tracking-wide rounded-md shadow-sm bottom-2 left-2 bg-n-slate-12 text-n-solid-1"
      >
        {{ selo }}
      </span>
    </span>
    <span class="flex flex-col min-w-0 gap-0.5 px-0.5">
      <span
        class="text-sm font-medium [overflow-wrap:anywhere] line-clamp-3 text-n-slate-12 group-hover:underline"
        :title="arquivo.nome"
      >
        {{ nomeVisivel }}
      </span>
      <span class="text-sm text-n-slate-11">{{ quando }}</span>
    </span>
  </component>
</template>
