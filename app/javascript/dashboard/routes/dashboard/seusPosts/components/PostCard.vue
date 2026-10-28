<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { dataCurta, formatar } from '../seusPostsHelpers';

// Seus posts (#2302): um post na grade, no mesmo cartão dos anúncios do painel de Anúncios (o nome com um selo só ao
// lado, os números em duas colunas, a foto na moldura 4:5 e um link que cobre o cartão inteiro). Post novo, ainda
// sem número da Meta, não mostra números: só quando eles chegam. Até o detalhe do post (F2, #2305), o link abre o
// post na rede.
const props = defineProps({
  post: { type: Object, required: true },
  // Como o post foi contra o normal dos posts do perfil: { nivel, texto } ou null (novo, sem números, impulsionado).
  veredito: { type: Object, default: null },
  // O post sem anúncio que mais apareceu no período.
  destaque: { type: Boolean, default: false },
});

const { locale, t } = useI18n();
const semImagem = ref(false);

const ICONE_DO_TIPO = {
  foto: 'i-lucide-image',
  video: 'i-lucide-play',
  carrossel: 'i-lucide-gallery-horizontal-end',
};

// As mesmas cores do veredito dos anúncios (VERDICT_CLASSES): sobe em verde, normal em azul, abaixo em âmbar.
const COR_DO_NIVEL = {
  TIMES: 'bg-n-teal-3 text-n-teal-11',
  DOUBLE: 'bg-n-teal-3 text-n-teal-11',
  WELL_ABOVE: 'bg-n-teal-3 text-n-teal-11',
  ABOVE: 'bg-n-teal-3 text-n-teal-11',
  SAME: 'bg-n-blue-3 text-n-blue-11',
  BELOW: 'bg-n-amber-3 text-n-amber-11',
  BOOSTED: 'bg-n-amber-3 text-n-amber-11',
};

const selo = computed(() => {
  if (!props.veredito) return null;
  return {
    texto: props.veredito.texto,
    cor: COR_DO_NIVEL[props.veredito.nivel],
    data: { 'data-seus-posts-veredito': props.veredito.nivel },
  };
});

// Post sem as vezes (Página sem Insights, número que não veio): a linha sai, em vez de um traço. No post
// impulsionado da Página, curtidas e comentários incluem o anúncio (só as vezes se separam): o megafone.
const numeros = computed(() => [
  ...(props.post.semInsights
    ? []
    : [
        {
          chave: 'views',
          label: t('SEUS_POSTS.POST.NUMBERS.VIEWS'),
          valor: formatar(props.post.apareceu, locale.value),
        },
      ]),
  {
    chave: 'likes',
    label: t('SEUS_POSTS.POST.NUMBERS.LIKES'),
    valor: formatar(props.post.curtidas, locale.value),
    anuncio: props.post.impulsionado,
  },
  {
    chave: 'comments',
    label: t('SEUS_POSTS.POST.NUMBERS.COMMENTS'),
    valor: formatar(props.post.comentarios, locale.value),
    anuncio: props.post.impulsionado,
  },
]);
const nome = computed(
  () => props.post.legenda || t(`SEUS_POSTS.CARD.NO_TEXT.${props.post.rede}`)
);
</script>

<template>
  <div
    :data-seus-posts-card="post.id"
    class="relative flex flex-col overflow-hidden rounded-xl bg-n-solid-1 ring-1 ring-n-weak transition hover:ring-n-slate-6 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
  >
    <!-- A moldura 4:5 do cartão de anúncio (#2010): a foto aparece inteira (vertical, feed ou quadrada) e a sobra é a
         própria foto desfocada, para a linha de cartões ficar alinhada sem cortar o post. -->
    <div class="relative aspect-[4/5] overflow-hidden bg-n-alpha-1">
      <template v-if="post.imagem && !semImagem">
        <img
          :src="post.imagem"
          alt=""
          aria-hidden="true"
          loading="lazy"
          class="absolute inset-0 size-full scale-110 object-cover blur-2xl brightness-90"
        />
        <img
          :src="post.imagem"
          alt=""
          loading="lazy"
          class="relative block size-full object-contain"
          @error="semImagem = true"
        />
      </template>
      <span
        v-else
        class="absolute inset-0 grid place-items-center text-n-slate-10"
        aria-hidden="true"
      >
        <span class="i-lucide-text size-8" />
      </span>
      <span
        v-if="post.tipo"
        class="absolute start-3 top-3 inline-flex items-center gap-1 rounded-full bg-n-heroi/80 px-2.5 py-1 text-xs font-medium text-white backdrop-blur"
      >
        <span
          :class="ICONE_DO_TIPO[post.tipo]"
          class="size-3.5"
          aria-hidden="true"
        />
        {{ $t(`SEUS_POSTS.CARD.TYPE.${post.tipo}`) }}
      </span>
    </div>
    <div class="flex flex-1 flex-col gap-4 p-4">
      <div class="flex flex-wrap items-start justify-between gap-x-3 gap-y-2">
        <span
          class="line-clamp-2 break-words text-sm font-semibold leading-snug text-n-slate-12"
        >
          {{ nome }}
        </span>
        <span
          v-if="selo"
          v-bind="selo.data"
          class="inline-flex flex-none items-center gap-1 whitespace-nowrap rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4"
          :class="selo.cor"
        >
          {{ selo.texto }}
        </span>
      </div>
      <p
        v-if="post.novo"
        data-seus-posts-sem-numeros
        class="m-0 flex items-center gap-2 rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-clock size-4 shrink-0" aria-hidden="true" />
        {{ $t('SEUS_POSTS.CARD.NUMBERS_SOON') }}
      </p>
      <dl v-else class="m-0 grid grid-cols-2 gap-x-3 gap-y-3">
        <div
          v-for="numero in numeros"
          :key="numero.chave"
          class="flex min-w-0 flex-col gap-1"
        >
          <dt class="text-xs text-n-slate-11">
            {{ numero.label }}
            <span
              v-if="numero.anuncio"
              data-seus-posts-marca-anuncio
              class="i-lucide-megaphone ms-0.5 inline-block size-3 align-[-1px] text-n-slate-10"
              :title="$t('SEUS_POSTS.TILES.MAYBE_ADS')"
            />
            <span v-if="numero.anuncio" class="sr-only">
              {{ $t('SEUS_POSTS.TILES.MAYBE_ADS') }}
            </span>
          </dt>
          <dd
            class="m-0 whitespace-nowrap text-base font-semibold tabular-nums text-n-slate-12"
          >
            {{ numero.valor }}
          </dd>
        </div>
      </dl>
      <p
        class="m-0 flex flex-wrap items-center gap-x-2 text-xs font-normal tabular-nums text-n-slate-11"
      >
        <span
          v-if="destaque"
          data-seus-posts-destaque
          class="inline-flex items-center gap-1 font-medium text-n-teal-11"
        >
          <span class="i-lucide-trophy size-3" aria-hidden="true" />
          {{ $t('SEUS_POSTS.CARD.BEST') }}
        </span>
        {{
          post.semInsights
            ? $t('SEUS_POSTS.CARD.PUBLISHED_NO_INSIGHTS', {
                date: dataCurta(post.publicadoEm, locale),
              })
            : $t('SEUS_POSTS.CARD.PUBLISHED', {
                date: dataCurta(post.publicadoEm, locale),
              })
        }}
      </p>
      <!-- O link cobre o cartão inteiro (after:inset-0): tocar em qualquer parte abre o post, e o leitor de tela
           ouve um só link com o nome dele. -->
      <a
        v-if="post.link"
        :href="post.link"
        target="_blank"
        rel="noopener noreferrer"
        :data-seus-posts-abrir="post.id"
        :aria-label="
          $t(`SEUS_POSTS.CARD.OPEN_LABEL.${post.rede}`, { name: nome })
        "
        class="mt-auto inline-flex min-h-11 items-center gap-1 self-start rounded-xl text-sm font-medium text-n-blue-11 no-underline focus-visible:outline-none after:absolute after:inset-0 after:rounded-xl after:content-['']"
      >
        {{ $t(`SEUS_POSTS.POST.OPEN.${post.rede}`) }}
        <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
      </a>
    </div>
  </div>
</template>
