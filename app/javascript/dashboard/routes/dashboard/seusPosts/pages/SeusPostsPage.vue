<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { useAlert } from 'dashboard/composables';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { useFacebookPageConnect } from 'dashboard/composables/useFacebookPageConnect';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import FBChannel from 'dashboard/api/channel/fbChannel';
import instagramClient from 'dashboard/api/channel/instagramClient';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import EstadoVazio from '../components/EstadoVazio.vue';
import NumeroQuadro from '../components/NumeroQuadro.vue';
import PostCard from '../components/PostCard.vue';
import { perfilParaTela } from '../seusPostsDados';
import {
  ICONE_DA_REDE,
  PERIODOS,
  PERIODO_PADRAO,
  comparacao,
  comparacaoCurta,
  formatar,
  legendaDoAnuncio,
  vereditoDoPost,
} from '../seusPostsHelpers';

// Seus posts (#2302, F1 #2304): página própria em Crescer. Usa as caixas do Instagram e da Página do Facebook, sem
// conexão própria. De cima para baixo: perfil e período, a frase do período, os números e a grade dos posts do
// período. Uma ação principal: abrir um post. Os comentários esperando e o cuidado chegam na F2 e na F3.
//
// Os dados vêm de GET seus_posts (SeusPosts::Leitura). Perfil e período ficam no endereço (?perfil=, ?dias=).
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();

const dias = computed(() => {
  const valor = Number(route.query.dias);
  return PERIODOS.includes(valor) ? valor : PERIODO_PADRAO;
});
const mudarQuery = query =>
  router.replace({ query: { ...route.query, ...query } });
const escolherDias = valor => mudarQuery({ dias: String(valor) });

const dados = ref(null);
const carregando = ref(true);
// 'rede' (falha de rede ou do servidor, com "Tentar de novo") ou 'acesso' (403: a função não abre Seus posts).
const erro = ref(null);
// Trocar 7 → 90 dias rápido: só a última leitura pedida vale.
let ultimoPedido = 0;
const carregar = async () => {
  ultimoPedido += 1;
  const pedido = ultimoPedido;
  carregando.value = true;
  erro.value = null;
  try {
    const { data } = await SeusPostsAPI.get({
      perfil: route.query.perfil || undefined,
      days: dias.value,
    });
    if (pedido === ultimoPedido) dados.value = data;
  } catch (error) {
    if (pedido !== ultimoPedido) return;
    const status = error?.response?.status;
    // Perfil do endereço que não é mais da conta: volta para o primeiro perfil.
    if (status === 404 && route.query.perfil) {
      mudarQuery({ perfil: undefined });
      return;
    }
    erro.value = status === 403 ? 'acesso' : 'rede';
  } finally {
    if (pedido === ultimoPedido) carregando.value = false;
  }
};
watch(() => [route.query.perfil, dias.value], carregar, { immediate: true });

const nomes = computed(() =>
  Object.fromEntries(
    (dados.value?.perfis || []).map(item => [item.id, item.name])
  )
);
const perfil = computed(() => {
  const lido = dados.value?.perfil;
  return lido ? perfilParaTela(lido, nomes.value[lido.id]) : null;
});
const perfis = computed(() => dados.value?.perfis || []);
const perfilId = computed({
  get: () => perfil.value?.id || '',
  set: valor => mudarQuery({ perfil: valor }),
});

// Perfil ainda não lido vai sem nome: a escolha diz a rede.
const nomeDoPerfil = item =>
  item.name
    ? t(`SEUS_POSTS.PROFILE.${item.network}`, { name: item.name })
    : t(`SEUS_POSTS.PROFILE_NO_NAME.${item.network}`);
const opcoesDePerfil = computed(() =>
  perfis.value.map(item => ({ value: item.id, label: nomeDoPerfil(item) }))
);
const tituloDoPerfil = computed(() =>
  perfil.value
    ? nomeDoPerfil({ network: perfil.value.rede, name: perfil.value.nome })
    : ''
);

const resumo = computed(() => perfil.value?.resumo);
// Abaixo disso o Instagram não manda quem começou a seguir.
const MIN_SEGUIDORES = 100;
const num = valor => formatar(valor, locale.value);
// Seguidores novos do período. A Meta manda quem começou a seguir (Instagram: follows_and_unfollows no lado FOLLOWER;
// Página: page_daily_follows_unique), não o saldo; negativo só por erro, e mesmo assim não vira "-3 começaram".
const mudancaDeSeguidores = novos => {
  if (novos === null) return null;
  if (novos < 0)
    return {
      texto: t('SEUS_POSTS.TILES.FOLLOWERS.LEFT', { count: num(-novos) }),
      tom: 'desce',
    };
  return {
    texto: t('SEUS_POSTS.TILES.FOLLOWERS.NEW', { count: num(novos) }),
    tom: novos > 0 ? 'sobe' : 'igual',
  };
};

const manchete = computed(() => {
  // Sem as vezes (a Meta não mandou) não é "não apareceram": isso só com zero de verdade.
  if (resumo.value?.apareceu === null)
    return t('SEUS_POSTS.HEADLINE.NO_NUMBER', { days: dias.value });
  if (!resumo.value?.apareceu)
    return t('SEUS_POSTS.HEADLINE.ZERO', { days: dias.value });
  return t(`SEUS_POSTS.HEADLINE.${perfil.value.rede}`, {
    count: num(resumo.value.apareceu),
  });
});
const mudancaDaManchete = computed(() => {
  if (!resumo.value) return null;
  if (resumo.value.primeiroPeriodo)
    return { texto: t('SEUS_POSTS.CHANGE.FIRST_PERIOD'), tom: 'igual' };
  return comparacao(
    resumo.value.apareceu,
    resumo.value.apareceuAntes,
    dias.value,
    t,
    locale.value
  );
});

const quadros = computed(() => {
  const r = resumo.value;
  const muda = (atual, antes) => comparacaoCurta(atual, antes, t, locale.value);
  // Só com o total abaixo do mínimo: total que a Meta não mandou fica "—", sem o aviso.
  const poucosSeguidores =
    r.seguidoresNovos === null &&
    r.seguidores !== null &&
    r.seguidores < MIN_SEGUIDORES;
  return [
    {
      nome: 'people',
      label: t('SEUS_POSTS.TILES.PEOPLE.LABEL'),
      // No Instagram é o teto: a mesma pessoa pode contar num post e num story.
      // Sem o número, só "—" (nunca "até —").
      valor:
        r.pessoasAte && r.pessoas !== null
          ? t('SEUS_POSTS.TILES.PEOPLE.UP_TO', { count: num(r.pessoas) })
          : num(r.pessoas),
      mudanca: muda(r.pessoas, r.pessoasAntes),
      ajuda: t(`SEUS_POSTS.TILES.PEOPLE.HELP_${perfil.value.rede}`),
      anuncio: r.lados.pessoas,
    },
    {
      nome: 'interactions',
      label: t('SEUS_POSTS.TILES.INTERACTIONS.LABEL'),
      valor: num(r.interacoes),
      mudanca: muda(r.interacoes, r.interacoesAntes),
      ajuda: t(`SEUS_POSTS.TILES.INTERACTIONS.HELP_${perfil.value.rede}`),
      anuncio: r.lados.interacoes,
    },
    {
      nome: 'followers',
      label: t('SEUS_POSTS.TILES.FOLLOWERS.LABEL'),
      valor: num(r.seguidores),
      // Quem começou a seguir vai na linha da comparação. Abaixo de 100 seguidores o Instagram não conta: o quadro
      // diz isso no lugar.
      mudanca: mudancaDeSeguidores(r.seguidoresNovos),
      extra: poucosSeguidores
        ? t('SEUS_POSTS.TILES.FOLLOWERS.FEW', { min: MIN_SEGUIDORES })
        : '',
      anuncio: r.lados.seguidores,
    },
    // Mensagens só para quem vê a caixa (parecer da Funções): sem a contagem, o quadro não aparece.
    ...(r.mensagens === null
      ? []
      : [
          {
            nome: 'messages',
            label: t('SEUS_POSTS.TILES.MESSAGES.LABEL'),
            valor: num(r.mensagens),
            mudanca: muda(r.mensagens, r.mensagensAntes),
            ajuda: t('SEUS_POSTS.TILES.MESSAGES.HELP'),
            anuncio: false,
          },
        ]),
  ];
});
const legenda = computed(() =>
  legendaDoAnuncio(quadros.value, t, locale.value)
);
// "Vezes que apareceu" está no herói; a explicação dela fica junto das outras.
const ajudas = computed(() => [
  {
    nome: 'views',
    label: t('SEUS_POSTS.TILES.VIEWS.LABEL'),
    ajuda: t('SEUS_POSTS.TILES.VIEWS.HELP'),
  },
  ...quadros.value.filter(quadro => quadro.ajuda),
]);
const tituloDosNumeros = computed(() =>
  resumo.value?.comparado
    ? t('SEUS_POSTS.TILES.TITLE', { days: dias.value })
    : t('SEUS_POSTS.TILES.TITLE_NO_COMPARE', { days: dias.value })
);

// Os mais novos primeiro, e os que tiveram anúncio no fim (não competem com os outros).
const posts = computed(() =>
  [...(perfil.value?.posts || [])].sort(
    (a, b) =>
      Number(a.impulsionado) - Number(b.impulsionado) ||
      new Date(b.publicadoEm) - new Date(a.publicadoEm)
  )
);
// O destaque diz "Mais apareceu sem anúncio": só entra post que se sabe sem anúncio (boosted false). No Instagram
// (boosted nil, não se sabe) não há destaque.
const melhorPost = computed(
  () =>
    posts.value
      .filter(
        post => post.apareceu && !post.semInsights && !post.podeTerAnuncio
      )
      .sort((a, b) => b.apareceu - a.apareceu)[0]
);
// Como cada post foi contra o normal do perfil, em palavras, no cartão.
const vereditoDe = post => {
  const { nivel, vezes } = vereditoDoPost(post, perfil.value.media);
  if (['NO_INSIGHTS', 'NEW', 'NO_NORMAL'].includes(nivel)) return null;
  if (nivel === 'BOOSTED')
    return { nivel, texto: t('SEUS_POSTS.CARD.HAD_ADS') };
  return { nivel, texto: t(`SEUS_POSTS.VS_NORMAL.${nivel}`, { times: vezes }) };
};

// "Ver conversas": a caixa abre em "Todas" (?aba=todas), como na aba de Anúncios.
const verConversas = computed(
  () => resumo.value?.mensagens !== null && perfil.value?.inboxId
);
const abrirConversas = () =>
  router.push({
    path: frontendURL(
      `accounts/${route.params.accountId}/inbox/${perfil.value.inboxId}`
    ),
    query: { aba: 'todas' },
  });
const abrirNaRede = () => window.open(perfil.value.link, '_blank', 'noopener');

// Sem caixa: a criação da caixa de sempre (inbox_manage). Caixa sem a permissão de números: reautoriza a mesma
// caixa (integration_manage, a régua do servidor para trocar a credencial). Página → Entrar com Facebook com
// read_insights, e a tela relê; Instagram → login do Instagram com instagram_business_manage_insights, que volta
// para esta página (purpose seus_posts). A volta do login do Instagram também exige inbox_manage (OauthBinding).
const podeCriarCaixa = usePermissionGranted('inbox_manage');
const podeReautorizar = usePermissionGranted('integration_manage');
// Sem a permissão dos números: o perfil todo, ou só a leitura dos posts (os números do perfil ficam).
const semPermissao = computed(
  () =>
    perfil.value?.status === 'needs_permission' ||
    perfil.value?.postsStatus === 'needs_permission'
);
const podeLiberar = computed(() => {
  if (!perfil.value?.inboxId || !podeReautorizar.value) return false;
  return perfil.value.rede === 'facebook' || podeCriarCaixa.value;
});
const conectar = canal =>
  router.push(
    frontendURL(
      `accounts/${route.params.accountId}/settings/inboxes/new/${canal}`
    )
  );

const { preloadSdk, login } = useFacebookPageConnect();
watch(
  () => semPermissao.value && perfil.value.rede === 'facebook',
  precisa => {
    if (precisa) preloadSdk().catch(() => {});
  },
  { immediate: true }
);
const ESCOPOS_DA_PAGINA = ['read_insights'];
const liberar = async () => {
  const { rede, inboxId } = perfil.value;
  try {
    if (rede === 'facebook') {
      const token = await login(ESCOPOS_DA_PAGINA);
      if (!token) return;
      await FBChannel.reauthorizeFacebookPage({
        omniauthToken: token,
        inboxId,
      });
      await carregar();
      return;
    }
    const { data } = await instagramClient.generateAuthorization({
      inbox_id: inboxId,
      return_to: 'meta_ads',
      purpose: 'seus_posts',
    });
    window.location.href = data.url;
  } catch {
    useAlert(t('SEUS_POSTS.NO_PERMISSION.ERROR'));
  }
};
</script>

<template>
  <section
    data-seus-posts
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div
      class="mx-auto flex w-full max-w-[90rem] flex-col gap-5 p-4 pb-24 sm:p-5 lg:p-8"
    >
      <header class="flex flex-col gap-1">
        <h1
          class="m-0 font-interDisplay text-[1.875rem] font-520 leading-tight tracking-[-0.02em] text-n-slate-12"
        >
          {{ $t('SEUS_POSTS.TITLE') }}
        </h1>
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{ $t('SEUS_POSTS.SUBTITLE') }}
        </p>
      </header>

      <div
        v-if="carregando && !dados"
        data-seus-posts-carregando
        class="flex flex-col gap-5"
        aria-busy="true"
        :aria-label="$t('SEUS_POSTS.LOADING')"
      >
        <div class="h-40 animate-pulse rounded-2xl bg-n-alpha-2" />
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div
            v-for="quadro in 4"
            :key="quadro"
            class="h-24 animate-pulse rounded-xl bg-n-alpha-2"
          />
        </div>
      </div>

      <!-- 403: a função da pessoa não abre Seus posts. Não é erro de rede: não há o que tentar de novo. -->
      <EstadoVazio
        v-else-if="erro === 'acesso'"
        data-seus-posts-sem-acesso
        icon="i-lucide-lock-keyhole"
        :titulo="$t('SEUS_POSTS.NO_ACCESS.TITLE')"
        :texto="$t('SEUS_POSTS.NO_ACCESS.TEXT')"
      />

      <EstadoVazio
        v-else-if="erro"
        data-seus-posts-erro
        role="alert"
        icon="i-lucide-cloud-off"
        :titulo="$t('SEUS_POSTS.ERROR.TITLE')"
        :texto="$t('SEUS_POSTS.ERROR.TEXT')"
        :botao="$t('SEUS_POSTS.ERROR.RETRY')"
        botao-icon="i-lucide-refresh-cw"
        @acao="carregar"
      />

      <!-- Sem caixa do Instagram nem da Página: 1 frase, 1 botão e o link da Página. -->
      <EstadoVazio
        v-else-if="!perfil"
        data-seus-posts-sem-caixa
        icon="i-ri-instagram-line"
        :titulo="$t('SEUS_POSTS.NO_INBOX.TITLE')"
        :texto="
          podeCriarCaixa
            ? $t('SEUS_POSTS.NO_INBOX.TEXT')
            : $t('SEUS_POSTS.NO_INBOX.ASK_ADMIN')
        "
        :botao="podeCriarCaixa ? $t('SEUS_POSTS.NO_INBOX.BUTTON') : ''"
        botao-icon="i-ri-instagram-line"
        @acao="conectar('instagram')"
      >
        <button
          v-if="podeCriarCaixa"
          type="button"
          class="min-h-11 self-start text-balance border-0 bg-transparent px-0 text-start text-sm font-medium text-n-blue-11 underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="conectar('facebook')"
        >
          {{ $t('SEUS_POSTS.NO_INBOX.PAGE') }}
        </button>
      </EstadoVazio>

      <template v-else>
        <!-- Altura fixa: sem o período (caixa sem permissão), o seletor não sobe. -->
        <div
          class="flex flex-col gap-3 sm:min-h-[3.25rem] sm:flex-row sm:items-center sm:justify-between"
          :class="{ 'opacity-60': carregando }"
        >
          <div v-if="perfis.length > 1" class="w-full sm:w-auto">
            <ChoiceSelect
              v-model="perfilId"
              data-seus-posts-perfil
              :options="opcoesDePerfil"
              :aria-label="$t('SEUS_POSTS.PROFILE_LABEL')"
              class="w-full sm:w-auto"
            />
          </div>
          <p
            v-else
            class="m-0 inline-flex min-h-11 items-center gap-2 text-sm font-semibold text-n-slate-12"
          >
            <span
              :class="ICONE_DA_REDE[perfil.rede]"
              class="size-5"
              aria-hidden="true"
            />
            {{ tituloDoPerfil }}
          </p>
          <div
            v-if="perfil.status === 'ok'"
            role="group"
            :aria-label="$t('SEUS_POSTS.PERIOD_LABEL')"
            class="grid w-full grid-cols-3 gap-1 rounded-2xl bg-n-alpha-1 p-1 sm:flex sm:w-fit"
          >
            <button
              v-for="valor in PERIODOS"
              :key="valor"
              type="button"
              :aria-pressed="valor === dias"
              :data-seus-posts-dias="valor"
              class="min-h-11 whitespace-nowrap rounded-xl border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="
                valor === dias
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
              "
              @click="escolherDias(valor)"
            >
              {{ $t('SEUS_POSTS.PERIODS', { days: valor }) }}
            </button>
          </div>
        </div>

        <!-- Caixa sem a permissão de números: um login e a pessoa volta para cá. Quem não pode trocar a credencial
             da caixa recebe o que pedir, sem botão. -->
        <EstadoVazio
          v-if="perfil.status === 'needs_permission'"
          data-seus-posts-sem-permissao
          icon="i-lucide-lock-keyhole"
          :titulo="$t(`SEUS_POSTS.NO_PERMISSION.${perfil.rede}`)"
          :texto="
            podeLiberar
              ? $t(`SEUS_POSTS.NO_PERMISSION.TEXT_${perfil.rede}`)
              : $t('SEUS_POSTS.NO_PERMISSION.ASK_ADMIN')
          "
          :botao="podeLiberar ? $t('SEUS_POSTS.NO_PERMISSION.BUTTON') : ''"
          botao-icon="i-lucide-key-round"
          @acao="liberar"
        />

        <!-- A Meta não respondeu neste perfil: os outros continuam na escolha de cima. -->
        <EstadoVazio
          v-else-if="perfil.status === 'unavailable'"
          data-seus-posts-indisponivel
          role="alert"
          icon="i-lucide-cloud-off"
          :titulo="$t('SEUS_POSTS.UNAVAILABLE.TITLE')"
          :texto="$t('SEUS_POSTS.UNAVAILABLE.TEXT')"
          :botao="$t('SEUS_POSTS.ERROR.RETRY')"
          botao-icon="i-lucide-refresh-cw"
          @acao="carregar"
        />

        <!-- Nenhum post no período: sem números zerados, só a frase e o botão. Posts que a Meta não mandou agora não
             são "você não postou": os números aparecem e a grade diz o que houve. -->
        <EstadoVazio
          v-else-if="!posts.length && perfil.postsStatus === 'ok'"
          data-seus-posts-sem-post
          icon="i-lucide-image-off"
          :titulo="$t('SEUS_POSTS.POSTS.EMPTY_PERIOD', { days: dias })"
          :texto="
            dias < 90
              ? $t('SEUS_POSTS.POSTS.EMPTY_PERIOD_TEXT')
              : $t(`SEUS_POSTS.POSTS.EMPTY_POST.${perfil.rede}`)
          "
          :botao="
            dias < 90 || perfil.link
              ? dias < 90
                ? $t('SEUS_POSTS.POSTS.SEE_90')
                : $t(`SEUS_POSTS.POST.OPEN.${perfil.rede}`)
              : ''
          "
          :botao-icon="dias < 90 ? '' : 'i-lucide-external-link'"
          @acao="dias < 90 ? escolherDias(90) : abrirNaRede()"
        />

        <template v-else>
          <!-- O mesmo herói do painel de Anúncios: período, a frase e a comparação. -->
          <div
            data-seus-posts-heroi
            class="relative flex flex-col gap-4 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 transition-opacity dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
            :class="{ 'opacity-60': carregando }"
          >
            <span
              aria-hidden="true"
              class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
            />
            <p class="relative m-0 text-sm font-medium text-white/70">
              {{ $t('SEUS_POSTS.RANGE', { days: dias }) }}
            </p>
            <p
              v-if="perfil.antigo"
              data-seus-posts-antigo
              class="relative m-0 flex items-center gap-1.5 text-sm text-white/80"
            >
              <span
                class="i-lucide-history size-4 shrink-0"
                aria-hidden="true"
              />
              {{ $t('SEUS_POSTS.STALE') }}
            </p>
            <div class="relative flex flex-col gap-2">
              <h2
                class="m-0 max-w-3xl text-balance text-2xl font-bold leading-tight tracking-tight text-white tabular-nums sm:text-3xl"
              >
                {{ manchete }}
              </h2>
              <p
                v-if="mudancaDaManchete"
                data-seus-posts-mudanca
                class="m-0 flex items-start gap-1.5 text-base font-medium text-white/90"
              >
                <span
                  :class="
                    mudancaDaManchete.tom === 'sobe'
                      ? 'i-lucide-trending-up text-n-teal-9'
                      : mudancaDaManchete.tom === 'desce'
                        ? 'i-lucide-trending-down text-n-ruby-9'
                        : 'i-lucide-equal'
                  "
                  class="mt-0.5 size-5 shrink-0"
                  aria-hidden="true"
                />
                {{ mudancaDaManchete.texto }}
              </p>
              <p class="m-0 text-sm text-white/70">
                {{ $t(`SEUS_POSTS.HEADLINE.ACCOUNT_NOTE.${perfil.rede}`) }}
              </p>
            </div>
          </div>

          <!-- Os números num painel, na grade fixa do painel de Anúncios: 2 colunas, 4 no desktop largo. -->
          <section
            data-seus-posts-numeros
            class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
          >
            <div class="flex flex-col gap-1">
              <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                {{ tituloDosNumeros }}
              </h2>
              <p
                data-seus-posts-legenda
                class="m-0 flex items-start gap-1.5 text-sm text-n-slate-11"
              >
                <span
                  class="i-lucide-megaphone mt-0.5 size-3.5 shrink-0 text-n-slate-10"
                  aria-hidden="true"
                />
                {{ legenda }}
              </p>
            </div>
            <dl
              class="m-0 grid grid-cols-2 gap-3"
              :class="
                quadros.length === 4 ? 'sm:grid-cols-4' : 'sm:grid-cols-3'
              "
            >
              <NumeroQuadro
                v-for="quadro in quadros"
                :key="quadro.nome"
                :data-seus-posts-quadro="quadro.nome"
                :label="quadro.label"
                :valor="quadro.valor"
                :mudanca="quadro.mudanca"
                :extra="quadro.extra"
                :anuncio="quadro.anuncio"
                :tem-mudanca="quadros.some(q => q.mudanca)"
                :tem-nota="quadros.some(q => q.extra)"
              />
            </dl>
            <!-- Embaixo da grade, junto da ajuda: no celular, no cabeçalho ele separava a legenda dos quadros. -->
            <div
              class="-mb-2 flex flex-wrap items-start justify-between gap-x-6"
            >
              <details class="group text-sm text-n-slate-11">
                <summary
                  class="inline-flex min-h-11 cursor-pointer list-none items-center gap-1 rounded-lg font-medium text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                >
                  <span
                    class="i-lucide-chevron-right size-4 transition-transform group-open:rotate-90"
                    aria-hidden="true"
                  />
                  {{ $t('SEUS_POSTS.TILES.WHAT_IS') }}
                </summary>
                <dl class="m-0 grid gap-x-6 gap-y-1 pb-1 ps-5 lg:grid-cols-3">
                  <div v-for="quadro in ajudas" :key="quadro.nome">
                    <dt class="inline font-semibold">{{ quadro.label }}:</dt>
                    {{ ' ' }}
                    <dd class="m-0 inline">{{ quadro.ajuda }}</dd>
                  </div>
                </dl>
              </details>
              <button
                v-if="verConversas"
                type="button"
                data-seus-posts-ver-conversas
                class="inline-flex min-h-11 items-center gap-1.5 rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                @click="abrirConversas"
              >
                {{ $t('SEUS_POSTS.MESSAGES.OPEN') }}
                <span
                  class="i-lucide-arrow-right size-3.5"
                  aria-hidden="true"
                />
              </button>
            </div>
          </section>

          <!-- A grade num painel, como a lista de anúncios do painel de Anúncios. -->
          <section
            class="flex flex-col gap-5 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
            data-seus-posts-grade
          >
            <div class="flex flex-col gap-1">
              <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                {{ $t('SEUS_POSTS.POSTS.TITLE', { days: dias }) }}
              </h2>
              <p
                v-if="perfil.postsCortados"
                data-seus-posts-cortados
                class="m-0 text-sm text-n-slate-11"
              >
                {{ $t('SEUS_POSTS.POSTS.TRUNCATED') }}
              </p>
              <p
                v-if="perfil.postsAntigos && !perfil.antigo"
                data-seus-posts-posts-antigos
                class="m-0 text-sm text-n-slate-11"
              >
                {{ $t('SEUS_POSTS.POSTS.STALE') }}
              </p>
            </div>
            <EstadoVazio
              v-if="perfil.postsStatus === 'needs_permission'"
              data-seus-posts-posts-sem-permissao
              icon="i-lucide-lock-keyhole"
              :titulo="$t(`SEUS_POSTS.NO_PERMISSION.${perfil.rede}`)"
              :texto="
                podeLiberar
                  ? $t(`SEUS_POSTS.NO_PERMISSION.TEXT_${perfil.rede}`)
                  : $t('SEUS_POSTS.NO_PERMISSION.ASK_ADMIN')
              "
              :botao="podeLiberar ? $t('SEUS_POSTS.NO_PERMISSION.BUTTON') : ''"
              botao-icon="i-lucide-key-round"
              @acao="liberar"
            />
            <EstadoVazio
              v-else-if="perfil.postsStatus === 'unavailable'"
              data-seus-posts-posts-indisponiveis
              role="alert"
              icon="i-lucide-cloud-off"
              :titulo="$t('SEUS_POSTS.POSTS.UNAVAILABLE.TITLE')"
              :texto="$t('SEUS_POSTS.POSTS.UNAVAILABLE.TEXT')"
              :botao="$t('SEUS_POSTS.ERROR.RETRY')"
              botao-icon="i-lucide-refresh-cw"
              @acao="carregar"
            />
            <ul
              v-else
              class="m-0 grid list-none items-stretch gap-5 p-0 sm:grid-cols-2 xl:grid-cols-3"
            >
              <li v-for="post in posts" :key="post.id" class="flex">
                <PostCard
                  :post="post"
                  :veredito="vereditoDe(post)"
                  :destaque="post.id === melhorPost?.id"
                  class="w-full"
                />
              </li>
            </ul>
          </section>
        </template>
      </template>
    </div>
  </section>
</template>
