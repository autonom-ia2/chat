<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import Button from 'dashboard/components-next/button/Button.vue';
import EstadoVazio from '../components/EstadoVazio.vue';
import NumeroQuadro from '../components/NumeroQuadro.vue';
import ComentarioLinha from '../components/ComentarioLinha.vue';
import { comentarioParaTela, postParaTela } from '../seusPostsDados';
import { formatar, intlLocale, vereditoDoPost } from '../seusPostsHelpers';
import { useLiberarAcesso } from '../useLiberarAcesso';

// Seus posts F2 (#2305): um post do perfil e os comentários dele, montado como o detalhe de um anúncio: o voltar, o
// herói (nome, como foi e quem espera você), a foto e o post à esquerda, os números à direita e os comentários
// embaixo, em largura total. Os dados vêm de GET seus_posts/posts/:post_id?perfil= (SeusPostsComentariosController):
// o post sai da mesma lista da página de Seus posts. Cada ação vai à Meta e a lista de comentários é lida de novo.
const { t, locale } = useI18n();
const route = useRoute();

const dados = ref(null);
const carregando = ref(true);
// 'acesso' (403: sem a chave ou sem ver a caixa), 'sumiu' (404: o post não está mais no perfil) ou 'rede'.
const erro = ref(null);
const comentarios = ref({
  status: null,
  lista: [],
  total: null,
  proximo: null,
});
const carregandoMais = ref(false);
// O id do comentário cuja ação está indo para a Meta.
const ocupado = ref(null);

const perfilId = computed(() => route.query.perfil);
const postId = computed(() => route.params.postId);

const guardarComentarios = (dadosDosComentarios, juntar = false) => {
  const lidos = (dadosDosComentarios?.comments || []).map(comentarioParaTela);
  comentarios.value = {
    status: dadosDosComentarios?.status || null,
    lista: juntar ? [...comentarios.value.lista, ...lidos] : lidos,
    total: juntar
      ? comentarios.value.total
      : (dadosDosComentarios?.total ?? null),
    proximo: dadosDosComentarios?.next_cursor || null,
  };
};

// Trocar de post ou de perfil no meio de uma leitura: só a resposta da leitura mais nova vale.
let leitura = 0;
const lerPost = async () => {
  leitura += 1;
  const minha = leitura;
  const { data } = await SeusPostsAPI.getPost({
    perfil: perfilId.value,
    postId: postId.value,
  });
  if (minha !== leitura) return;
  dados.value = data;
  guardarComentarios(data.comments);
};
const carregar = async () => {
  carregando.value = true;
  erro.value = null;
  try {
    await lerPost();
  } catch (error) {
    const status = error?.response?.status;
    if (status === 403) erro.value = 'acesso';
    else if (status === 404) erro.value = 'sumiu';
    else erro.value = 'rede';
  } finally {
    carregando.value = false;
  }
};
watch(() => [perfilId.value, postId.value], carregar, { immediate: true });

const verMais = async () => {
  carregandoMais.value = true;
  try {
    const { data } = await SeusPostsAPI.getComments({
      perfil: perfilId.value,
      postId: postId.value,
      after: comentarios.value.proximo,
    });
    guardarComentarios(data, true);
  } catch {
    useAlert(t('SEUS_POSTS.POST.COMMENTS.ERROR'));
  } finally {
    carregandoMais.value = false;
  }
};

const rede = computed(() => dados.value?.perfil?.network);
const post = computed(() =>
  dados.value?.post ? postParaTela(dados.value.post, rede.value) : null
);
const perfil = computed(() =>
  dados.value?.perfil
    ? { rede: rede.value, inboxId: dados.value.perfil.inbox_id }
    : null
);
const num = valor => formatar(valor, locale.value);

const voltar = computed(() => ({
  name: 'seus_posts_index',
  params: { accountId: route.params.accountId },
  query: { perfil: perfilId.value, dias: route.query.dias },
}));

const publicado = computed(() =>
  new Date(post.value.publicadoEm).toLocaleDateString(
    intlLocale(locale.value),
    { day: 'numeric', month: 'long' }
  )
);
// O nome do post é a primeira frase da legenda, como o nome de um anúncio; o cartão "O post" mostra só o resto.
const titulo = computed(() => {
  const legenda = post.value.legenda;
  if (!legenda) return t(`SEUS_POSTS.CARD.NO_TEXT.${rede.value}`);
  const primeira = legenda.split('. ')[0].trim();
  return primeira.endsWith('.') ? primeira.slice(0, -1) : primeira;
});
const restoDaLegenda = computed(() => {
  const legenda = post.value.legenda;
  if (!legenda) return '';
  const resto = legenda.slice(titulo.value.length);
  return (resto.startsWith('.') ? resto.slice(1) : resto).trim();
});

// Como o post foi contra o normal dos posts do perfil, numa frase, no herói.
const resumo = computed(() => {
  const media = { apareceu: dados.value?.normal?.views ?? null };
  const { nivel, vezes } = vereditoDoPost(post.value, media);
  return t(`SEUS_POSTS.POST.SUMMARY.${nivel}`, { times: vezes });
});

// Os números do post em quatro quadros, como o detalhe de anúncio, e os outros numa linha curta embaixo. No
// Instagram, vezes, curtidas e comentários são sem anúncio; pessoas, salvaram e compartilharam podem incluir. Na
// Página, só as vezes se separam: o resto inclui o anúncio quando houve. O Facebook não conta quem salvou: no lugar,
// cliques no post.
const QUADROS = [
  ['apareceu', 'VIEWS'],
  ['pessoas', 'PEOPLE'],
  ['curtidas', 'LIKES'],
  ['comentarios', 'COMMENTS'],
];
const OUTROS = {
  instagram: [
    ['salvaram', 'SAVED'],
    ['compartilharam', 'SHARED'],
  ],
  facebook: [
    ['cliques', 'CLICKED'],
    ['compartilharam', 'SHARED'],
  ],
};
const SEM_INSIGHTS = ['curtidas', 'comentarios'];
const podeTerAnuncio = chave => {
  if (chave === 'apareceu') return false;
  if (rede.value === 'instagram') return chave === 'pessoas';
  return post.value.podeTerAnuncio;
};
const quadros = computed(() =>
  QUADROS.filter(
    ([chave]) => !post.value.semInsights || SEM_INSIGHTS.includes(chave)
  ).map(([chave, rotulo]) => ({
    nome: chave,
    label: t(`SEUS_POSTS.POST.NUMBERS.${rotulo}`),
    valor: num(post.value[chave]),
    anuncio: podeTerAnuncio(chave),
  }))
);
const outros = computed(() =>
  post.value.semInsights
    ? ''
    : OUTROS[rede.value]
        .filter(([chave]) => post.value[chave] !== null)
        .map(([chave, rotulo]) =>
          t(
            `SEUS_POSTS.POST.NUMBERS.${rotulo}`,
            { count: num(post.value[chave]) },
            post.value[chave]
          )
        )
        .join(' · ')
);
const ladoDoAnuncio = computed(() => {
  if (post.value.semInsights) return '';
  if (post.value.impulsionado)
    return t('SEUS_POSTS.POST.SIDE.BOOSTED', {
      name: t('SEUS_POSTS.POST.NUMBERS.VIEWS'),
    });
  if (rede.value === 'instagram') return t('SEUS_POSTS.POST.SIDE.INSTAGRAM');
  return t('SEUS_POSTS.TILES.LEGEND_NONE');
});

// Comentários: filtro simples, contado da lista que já veio. Aba sem nada não aparece (Todos sempre).
const FILTROS = [
  ['all', null],
  ['esperando', 'esperando'],
  ['privado', 'privado'],
  ['escondido', 'escondido'],
];
const contagem = computed(() => {
  const conta = { all: comentarios.value.lista.length };
  FILTROS.slice(1).forEach(([chave, estado]) => {
    conta[chave] = comentarios.value.lista.filter(
      comentario => comentario.estado === estado
    ).length;
  });
  return conta;
});
const filtros = computed(() =>
  FILTROS.filter(([chave]) => chave === 'all' || contagem.value[chave])
);
const filtro = ref('all');
// Respondeu o último da aba e ela sumiu: volta para Todos.
watch(filtros, lista => {
  if (!lista.some(([chave]) => chave === filtro.value)) filtro.value = 'all';
});
const visiveis = computed(() => {
  const estado = FILTROS.find(([chave]) => chave === filtro.value)[1];
  return estado
    ? comentarios.value.lista.filter(comentario => comentario.estado === estado)
    : comentarios.value.lista;
});
// Quem espera no herói é a contagem do servidor, a mesma do cartão da lista (até 50 comentários, depois "ou mais"); as
// abas contam só os comentários já carregados.
const esperandoNoHeroi = computed(() => {
  const numero = num(post.value.esperando);
  return post.value.esperandoMais
    ? t('SEUS_POSTS.CARD.OR_MORE', { count: numero })
    : numero;
});
const listaDeComentarios = ref(null);
const verEsperando = () => {
  filtro.value = 'esperando';
  listaDeComentarios.value?.scrollIntoView({ behavior: 'smooth' });
};

// Cada ação vai à Meta; depois, o post é lido de novo: a resposta, esconder e o privado mudam a linha e quem espera.
// Sem a permissão de comentários, a lista vira o "Libere o acesso"; outra falha, um aviso.
const agir = async (comentario, chamada, sucesso, pronto = () => {}) => {
  ocupado.value = comentario.id;
  const alvo = {
    perfil: perfilId.value,
    postId: postId.value,
    commentId: comentario.id,
  };
  try {
    await chamada(alvo);
  } catch (error) {
    const codigo = error?.response?.data?.error;
    if (codigo === 'needs_permission')
      comentarios.value = { ...comentarios.value, status: 'needs_permission' };
    else
      useAlert(
        t(
          `SEUS_POSTS.POST.COMMENTS.ERRORS.${codigo}`,
          t('SEUS_POSTS.POST.COMMENTS.ERROR')
        )
      );
    ocupado.value = null;
    return;
  }
  pronto();
  useAlert(t(`SEUS_POSTS.POST.COMMENTS.DONE.${sucesso}`));
  try {
    await lerPost();
  } catch {
    // A ação valeu; só a lista nova não veio agora. Fica a de antes, sem aviso de erro.
  } finally {
    ocupado.value = null;
  }
};
const responder = (comentario, content, pronto) =>
  agir(
    comentario,
    alvo => SeusPostsAPI.reply({ ...alvo, content }),
    'reply',
    pronto
  );
const mandarPrivado = (comentario, content, pronto) =>
  agir(
    comentario,
    alvo => SeusPostsAPI.privateReply({ ...alvo, content }),
    'private',
    pronto
  );
const esconder = (comentario, hidden) =>
  agir(
    comentario,
    alvo => SeusPostsAPI.hide({ ...alvo, hidden }),
    hidden ? 'hide' : 'show'
  );
const apagar = comentario =>
  agir(comentario, alvo => SeusPostsAPI.removeComment(alvo), 'delete');
const liberarPrivado = comentario =>
  agir(comentario, alvo => SeusPostsAPI.releasePrivateReply(alvo), 'release');

const semPermissao = computed(
  () => comentarios.value.status === 'needs_permission'
);
const { podeLiberar, liberar } = useLiberarAcesso({
  perfil,
  precisa: semPermissao,
  reler: carregar,
});

const ICONE_DO_TIPO = {
  foto: 'i-lucide-image',
  video: 'i-lucide-play',
  carrossel: 'i-lucide-gallery-horizontal-end',
};
// Os botões de borda do detalhe de anúncio (voltar).
const BOTAO_DE_BORDA =
  'inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
</script>

<template>
  <section
    data-seus-posts-post
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div
      class="mx-auto flex w-full max-w-[90rem] flex-col gap-5 p-4 pb-24 sm:p-5 lg:p-8"
    >
      <router-link
        :to="voltar"
        data-seus-posts-voltar
        :class="BOTAO_DE_BORDA"
        class="self-start"
      >
        <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
        {{ $t('SEUS_POSTS.POST.BACK') }}
      </router-link>

      <p v-if="carregando && !dados" class="m-0 text-sm text-n-slate-11">
        {{ $t('SEUS_POSTS.LOADING') }}
      </p>
      <EstadoVazio
        v-else-if="erro === 'acesso'"
        data-seus-posts-post-sem-acesso
        icon="i-lucide-lock"
        :titulo="$t('SEUS_POSTS.POST.NO_ACCESS.TITLE')"
        :texto="$t('SEUS_POSTS.POST.NO_ACCESS.TEXT')"
      />
      <EstadoVazio
        v-else-if="erro === 'sumiu'"
        data-seus-posts-post-sumiu
        icon="i-lucide-image-off"
        :titulo="$t('SEUS_POSTS.POST.GONE.TITLE')"
        :texto="$t('SEUS_POSTS.POST.GONE.TEXT')"
      />
      <EstadoVazio
        v-else-if="erro"
        data-seus-posts-post-erro
        role="alert"
        icon="i-lucide-cloud-off"
        :titulo="$t('SEUS_POSTS.ERROR.TITLE')"
        :texto="$t('SEUS_POSTS.ERROR.TEXT')"
        :botao="$t('SEUS_POSTS.ERROR.RETRY')"
        botao-icon="i-lucide-refresh-cw"
        @acao="carregar"
      />
      <EstadoVazio
        v-else-if="dados && dados.status === 'needs_permission'"
        data-seus-posts-post-sem-permissao
        icon="i-lucide-lock-keyhole"
        :titulo="$t(`SEUS_POSTS.NO_PERMISSION.${rede}`)"
        :texto="
          podeLiberar
            ? $t(`SEUS_POSTS.NO_PERMISSION.TEXT_${rede}`)
            : $t('SEUS_POSTS.NO_PERMISSION.ASK_ADMIN')
        "
        :botao="podeLiberar ? $t('SEUS_POSTS.NO_PERMISSION.BUTTON') : ''"
        botao-icon="i-lucide-key-round"
        @acao="liberar"
      />
      <EstadoVazio
        v-else-if="dados && !post"
        data-seus-posts-post-indisponivel
        role="alert"
        icon="i-lucide-cloud-off"
        :titulo="$t('SEUS_POSTS.POSTS.UNAVAILABLE.TITLE')"
        :texto="$t('SEUS_POSTS.POSTS.UNAVAILABLE.TEXT')"
        :botao="$t('SEUS_POSTS.ERROR.RETRY')"
        botao-icon="i-lucide-refresh-cw"
        @acao="carregar"
      />

      <template v-else-if="post">
        <header
          data-seus-posts-heroi-post
          class="relative flex flex-col gap-2 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
        >
          <span
            aria-hidden="true"
            class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
          />
          <p class="relative m-0 text-sm font-medium text-white/70">
            {{
              $t(`SEUS_POSTS.POST.HERO_CONTEXT.${rede}`, { date: publicado })
            }}
          </p>
          <h1
            class="relative m-0 text-balance text-2xl font-bold leading-tight tracking-tight text-white sm:text-3xl"
          >
            {{ titulo }}
          </h1>
          <p
            data-seus-posts-como-foi
            class="relative m-0 max-w-3xl text-pretty text-base text-white/80"
          >
            {{ resumo }}
          </p>
          <div
            v-if="post.esperando"
            data-seus-posts-esperando-heroi
            class="relative flex flex-wrap items-center gap-3 pt-2"
          >
            <span
              class="inline-flex min-h-8 items-center gap-2 rounded-full bg-white/10 px-3 text-sm font-medium text-white/80"
            >
              <span
                class="size-2 rounded-full bg-n-amber-9"
                aria-hidden="true"
              />
              {{
                $t(
                  'SEUS_POSTS.CARD.WAITING',
                  { count: esperandoNoHeroi },
                  post.esperandoMais ? 2 : post.esperando
                )
              }}
            </span>
            <button
              type="button"
              data-seus-posts-ver-esperando
              class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border-0 bg-white px-4 text-sm font-520 text-n-heroi hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white max-sm:w-full"
              @click="verEsperando"
            >
              <span class="i-lucide-hand size-4" aria-hidden="true" />
              {{ $t('SEUS_POSTS.POST.SEE_WAITING') }}
            </button>
          </div>
        </header>

        <div
          class="grid items-start gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]"
        >
          <!-- No desktop a foto acompanha a rolagem: a coluna da direita é mais longa. -->
          <div
            class="flex flex-col gap-5 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto lg:overscroll-contain"
          >
            <figure
              class="m-0 flex flex-col gap-2 overflow-hidden rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
            >
              <div class="relative flex justify-center bg-n-alpha-1">
                <img
                  v-if="post.imagem"
                  :src="post.imagem"
                  alt=""
                  class="block h-auto max-h-[26rem] w-full object-contain lg:max-h-[40rem]"
                />
                <span
                  v-else
                  class="grid h-48 w-full place-items-center text-n-slate-10"
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
              <figcaption v-if="post.link" class="px-4 pb-3">
                <a
                  :href="post.link"
                  target="_blank"
                  rel="noopener noreferrer"
                  data-seus-posts-abrir-na-rede
                  class="inline-flex min-h-11 items-center gap-1.5 rounded-xl text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                >
                  {{ $t(`SEUS_POSTS.POST.OPEN.${rede}`) }}
                  <span
                    class="i-lucide-external-link size-3.5"
                    aria-hidden="true"
                  />
                </a>
              </figcaption>
            </figure>
            <section
              v-if="restoDaLegenda"
              data-seus-posts-legenda
              class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
            >
              <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                {{ $t('SEUS_POSTS.POST.POST_TITLE') }}
              </h2>
              <p
                class="m-0 whitespace-pre-line text-pretty text-base leading-relaxed text-n-slate-12"
              >
                {{ restoDaLegenda }}
              </p>
            </section>
          </div>

          <div class="flex flex-col gap-5">
            <dl
              data-seus-posts-numeros
              class="m-0 grid grid-cols-2 gap-x-3 gap-y-3 sm:grid-cols-4 lg:grid-cols-2 2xl:grid-cols-4"
              :aria-label="$t('SEUS_POSTS.POST.NUMBERS.TITLE')"
            >
              <NumeroQuadro
                v-for="quadro in quadros"
                :key="quadro.nome"
                :data-seus-posts-numero="quadro.nome"
                :label="quadro.label"
                :valor="quadro.valor"
                :anuncio="quadro.anuncio"
              />
            </dl>
            <section
              v-if="outros || ladoDoAnuncio"
              data-seus-posts-sobre-numeros
              class="flex flex-col gap-2 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
            >
              <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                {{ $t('SEUS_POSTS.POST.ABOUT_NUMBERS') }}
              </h2>
              <p
                v-if="outros"
                data-seus-posts-outros
                class="m-0 text-base tabular-nums text-n-slate-12"
              >
                {{ outros }}
              </p>
              <p
                v-if="ladoDoAnuncio"
                data-seus-posts-lado
                class="m-0 text-sm text-n-slate-11"
              >
                {{ ladoDoAnuncio }}
              </p>
            </section>
          </div>
        </div>

        <section
          ref="listaDeComentarios"
          class="flex scroll-mt-4 flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
          data-seus-posts-comentarios
        >
          <div
            class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <h2 class="m-0 text-sm font-semibold text-n-slate-11">
              {{
                comentarios.total === null
                  ? $t('SEUS_POSTS.POST.COMMENTS.TITLE')
                  : $t('SEUS_POSTS.POST.COMMENTS.TITLE_COUNT', {
                      count: num(comentarios.total),
                    })
              }}
            </h2>
            <div v-if="filtros.length > 1" class="sm:-my-2">
              <div
                role="group"
                :aria-label="$t('SEUS_POSTS.POST.COMMENTS.FILTER_LABEL')"
                class="flex flex-wrap gap-1 rounded-2xl bg-n-alpha-1 p-1 sm:w-max sm:flex-nowrap"
              >
                <button
                  v-for="[chave] in filtros"
                  :key="chave"
                  type="button"
                  :aria-pressed="filtro === chave"
                  :data-seus-posts-comentarios-filtro="chave"
                  class="min-h-11 shrink-0 whitespace-nowrap rounded-xl border-0 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                  :class="
                    filtro === chave
                      ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                      : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="filtro = chave"
                >
                  {{ $t(`SEUS_POSTS.POST.COMMENTS.FILTERS.${chave}`) }}
                  <span class="ms-1.5 tabular-nums text-n-slate-11">
                    {{ contagem[chave] }}
                  </span>
                </button>
              </div>
            </div>
          </div>

          <EstadoVazio
            v-if="semPermissao"
            data-seus-posts-comentarios-sem-permissao
            icon="i-lucide-lock-keyhole"
            :titulo="$t('SEUS_POSTS.COMMENTS_ACCESS.TITLE')"
            :texto="
              podeLiberar
                ? $t('SEUS_POSTS.COMMENTS_ACCESS.TEXT')
                : $t('SEUS_POSTS.COMMENTS_ACCESS.ASK_ADMIN')
            "
            :botao="podeLiberar ? $t('SEUS_POSTS.NO_PERMISSION.BUTTON') : ''"
            botao-icon="i-lucide-key-round"
            @acao="liberar"
          />
          <EstadoVazio
            v-else-if="comentarios.status && comentarios.status !== 'ready'"
            data-seus-posts-comentarios-indisponiveis
            role="alert"
            icon="i-lucide-cloud-off"
            :titulo="$t('SEUS_POSTS.POST.COMMENTS.UNAVAILABLE')"
            :botao="$t('SEUS_POSTS.ERROR.RETRY')"
            botao-icon="i-lucide-refresh-cw"
            @acao="carregar"
          />
          <p
            v-else-if="!visiveis.length"
            class="m-0 py-4 text-sm text-n-slate-11"
          >
            {{ $t('SEUS_POSTS.POST.COMMENTS.EMPTY') }}
          </p>
          <template v-else>
            <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
              <ComentarioLinha
                v-for="comentario in visiveis"
                :key="comentario.id"
                :comentario="comentario"
                :ocupado="ocupado === comentario.id"
                @responder="
                  (texto, pronto) => responder(comentario, texto, pronto)
                "
                @privado="
                  (texto, pronto) => mandarPrivado(comentario, texto, pronto)
                "
                @esconder="hidden => esconder(comentario, hidden)"
                @apagar="apagar(comentario)"
                @liberar="liberarPrivado(comentario)"
              />
            </ul>
            <Button
              v-if="comentarios.proximo"
              data-seus-posts-ver-mais
              variant="faded"
              color="slate"
              :is-loading="carregandoMais"
              :label="$t('SEUS_POSTS.POST.COMMENTS.MORE_COMMENTS')"
              class="!min-h-11 self-start !rounded-xl"
              @click="verMais"
            />
          </template>
        </section>
      </template>
    </div>
  </section>
</template>
