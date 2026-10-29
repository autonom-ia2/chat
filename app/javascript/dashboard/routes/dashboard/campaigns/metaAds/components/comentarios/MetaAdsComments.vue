<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MetaAdsCommentRow from './MetaAdsCommentRow.vue';

// Anúncios da Meta: os comentários do anúncio, uma aba por lugar onde ele aparece (Instagram #2196, Facebook #2197).
// Cada aba traz o seu adaptador (comentariosInstagram.js, comentariosFacebook.js), todos na mesma forma, sempre com o
// anúncio primeiro (o servidor só age em comentário do post do anúncio): listar(adId, { locale }), mais(adId, cursor),
// responder(adId, id, texto), ocultar(adId, id, hidden), apagar(adId, id), privado(adId, id, texto) e
// entrar(status, adId). Esta casca não sabe de plataforma. Aba sem post (`no_post`) não aparece; sem nenhuma aba, a seção some.
//
// O que a dona procura é quem ficou sem resposta: o selo e a contagem da aba são só desses (sem resposta pública da
// própria conta e sem resposta no privado). A lista começa curta e cresce com "Ver mais comentários".
//
// Uma aba pode trazer uma linha fixa no topo (`<ABA>.NOTE`): no Facebook, que a resposta é só pública.
//
// Ver é `meta_ads_view`; responder, ocultar, apagar e responder no privado só com `canManage` (`meta_ads_manage`).
// Aba que não pode ser lida (`needs_login`, `not_connected`, `no_inbox`, `not_inbox_member`) mostra um cartão com o
// motivo. Ler e agir pedem ver a caixa da rede (Instagram #2358, Facebook #2359): fora dela, `not_inbox_member`. O
// botão do cartão é de quem pode resolver: entrar de novo, `canManage`; conectar a caixa que falta (`no_inbox`,
// #2359), `canCreateInbox` (`inbox_manage`). A aba pode afinar quem entra com `podeEntrar(status)` (no Instagram,
// conectar pede inbox_manage e entrar de novo pede também integration_manage, #2358). Os demais leem a quem pedir
// (`<STATUS>_ASK`). Sem `<STATUS>_BUTTON` (fora da caixa), não há botão.
// Apagar some com o comentário de vez: pede confirmação citando o texto. Depois de cada ação a aba é lida de novo.
const props = defineProps({
  adId: { type: String, required: true },
  // [{ key: 'INSTAGRAM' | 'FACEBOOK', adaptador, podeEntrar?(status) }]
  abas: { type: Array, required: true },
  canManage: { type: Boolean, default: false },
  canCreateInbox: { type: Boolean, default: false },
});

const { t, te, locale } = useI18n();

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.COMMENTS';
const FIRST_PAGE = 3;
const QUOTE_LIMIT = 140;
const ICONS = {
  INSTAGRAM: 'i-lucide-instagram',
  FACEBOOK: 'i-lucide-facebook',
};

const results = ref({});
const failed = ref({});
const loading = ref(true);
const active = ref(null);
const shown = ref(FIRST_PAGE);
const loadingMore = ref(false);
const deleting = ref(null);
const deleteDialog = ref(null);
const busy = ref(false);
const tabRefs = ref([]);

const visible = computed(() =>
  props.abas.filter(aba => {
    const result = results.value[aba.key];
    return failed.value[aba.key] || (result && result.status !== 'no_post');
  })
);
const current = computed(
  () => visible.value.find(aba => aba.key === active.value) || visible.value[0]
);
const result = computed(() => results.value[current.value?.key] || null);
const status = computed(() => result.value?.status || 'ready');
const BLOCKED = [
  'needs_login',
  'not_connected',
  'no_inbox',
  'not_inbox_member',
];
const blocked = computed(() => BLOCKED.includes(status.value));
const statusKey = computed(
  () => `${KEY}.${current.value?.key}.${status.value.toUpperCase()}`
);
const canFix = computed(() => {
  if (status.value === 'no_inbox') return props.canCreateInbox;
  return props.canManage && (current.value.podeEntrar?.(status.value) ?? true);
});
const showFix = computed(() => canFix.value && te(`${statusKey.value}_BUTTON`));
const showAsk = computed(() => !canFix.value && te(`${statusKey.value}_ASK`));
const unknownAuthorKey = computed(
  () => `${KEY}.${current.value.key}.UNKNOWN_AUTHOR`
);

const isUnanswered = comment =>
  !comment.author?.is_page &&
  !comment.hidden &&
  !comment.private_reply &&
  !comment.replies?.some(reply => reply.author?.is_page);
const unansweredCount = key =>
  (results.value[key]?.comments || []).filter(isUnanswered).length;

const comments = computed(() =>
  (result.value?.comments || []).slice(0, shown.value)
);
const canShowMore = computed(
  () =>
    (result.value?.comments?.length || 0) > shown.value ||
    Boolean(result.value?.next_cursor)
);

const read = async aba => {
  try {
    const data = await aba.adaptador.listar(props.adId, {
      locale: locale.value,
    });
    results.value = { ...results.value, [aba.key]: data };
    failed.value = { ...failed.value, [aba.key]: false };
  } catch {
    failed.value = { ...failed.value, [aba.key]: true };
  }
};

const load = async () => {
  loading.value = true;
  results.value = {};
  failed.value = {};
  shown.value = FIRST_PAGE;
  await Promise.all(props.abas.map(read));
  loading.value = false;
};

// O idioma do painel pode chegar depois da primeira leitura: a lista é lida de novo nele, antes de qualquer ação.
watch([() => props.adId, locale], load);
onMounted(load);

const select = async index => {
  const aba = visible.value[index];
  if (!aba) return;
  active.value = aba.key;
  shown.value = FIRST_PAGE;
  await nextTick();
  tabRefs.value[index]?.focus();
};

// Abas no padrão WAI-ARIA: setas trocam de aba, Home e End vão às pontas.
const onTabKey = (event, index) => {
  const last = visible.value.length - 1;
  const next = {
    ArrowRight: index === last ? 0 : index + 1,
    ArrowLeft: index === 0 ? last : index - 1,
    Home: 0,
    End: last,
  }[event.key];
  if (next === undefined) return;
  event.preventDefault();
  select(next);
};

// Primeiro mostra o que já veio; quando acaba, pede a próxima página à Meta.
const more = async () => {
  if (result.value.comments.length > shown.value) {
    shown.value += FIRST_PAGE * 2;
    return;
  }
  // A aba e o que ela tinha antes da espera: trocar de aba no meio não junta a página na aba errada.
  const aba = current.value;
  const before = result.value;
  loadingMore.value = true;
  try {
    const data = await aba.adaptador.mais(props.adId, before.next_cursor);
    results.value = {
      ...results.value,
      [aba.key]: {
        ...before,
        comments: [...before.comments, ...data.comments],
        next_cursor: data.next_cursor,
      },
    };
    shown.value += FIRST_PAGE * 2;
  } catch {
    useAlert(t(`${KEY}.ERROR`));
  } finally {
    loadingMore.value = false;
  }
};

// Toda ação: chama o adaptador, avisa e lê a aba de novo. Recusa da Meta vira aviso, sem tirar nada da tela: numa
// resposta, o texto digitado continua na caixa (ACTION_ERROR); ao ocultar ou apagar, nada mudou (MANAGE_ERROR).
// Quando o servidor diz o motivo (`ERRORS.<CODE>`: privado já enviado, prazo vencido, falta permissão…), o aviso diz
// esse motivo; sem permissão ou sem a caixa da Página (#2359), a aba é lida de novo e mostra o cartão. O texto da
// própria aba (`<ABA>.ERRORS.<CODE>`, que diz a rede certa) vem antes do comum.
const REREAD = ['NEEDS_LOGIN', 'NO_INBOX', 'NOT_INBOX_MEMBER'];
const errorKey = (aba, code, failure) =>
  [`${KEY}.${aba.key}.ERRORS.${code}`, `${KEY}.ERRORS.${code}`].find(
    key => code && te(key)
  ) || `${KEY}.${failure}`;

const act = async (call, done, failure = 'ACTION_ERROR') => {
  const aba = current.value;
  try {
    await call(aba.adaptador);
    useAlert(t(`${KEY}.${done}`));
    await read(aba);
    return true;
  } catch (error) {
    const code = String(error?.response?.data?.error || '').toUpperCase();
    useAlert(t(errorKey(aba, code, failure)));
    if (REREAD.includes(code) || code.startsWith('PRIVATE_REPLY'))
      await read(aba);
    return false;
  }
};

// Entrar de novo (ou conectar) sai do painel para o login do Instagram. Trocar a credencial da caixa é de quem
// administra as integrações: sem essa permissão, o servidor recusa e o aviso diz a quem pedir.
const login = async state => {
  try {
    await current.value.adaptador.entrar?.(state, props.adId);
  } catch (error) {
    const forbidden = error?.response?.status === 403;
    useAlert(t(`${KEY}.${forbidden ? 'LOGIN_ADMIN' : 'ACTION_ERROR'}`));
  }
};

const authorName = comment =>
  comment.author?.username
    ? `@${comment.author.username}`
    : comment.author?.name || t(unknownAuthorKey.value);

const quote = comment => {
  const text = (comment.text || '').trim();
  return text.length > QUOTE_LIMIT
    ? `${text.slice(0, QUOTE_LIMIT).trimEnd()}…`
    : text;
};

const acoes = {
  responder: (comment, texto) =>
    act(
      adaptador => adaptador.responder(props.adId, comment.id, texto),
      'REPLY_DONE'
    ),
  privado: (comment, texto) =>
    act(
      adaptador => adaptador.privado(props.adId, comment.id, texto),
      'PRIVATE_DONE'
    ),
  liberar: comment =>
    act(
      adaptador => adaptador.liberar(props.adId, comment.id),
      'PRIVATE_RELEASED'
    ),
  ocultar: (comment, hidden) =>
    act(
      adaptador => adaptador.ocultar(props.adId, comment.id, hidden),
      hidden ? 'HIDE_DONE' : 'SHOW_DONE',
      'MANAGE_ERROR'
    ),
  apagar: comment => {
    deleting.value = comment;
    deleteDialog.value?.open();
  },
};

const confirmDelete = async () => {
  busy.value = true;
  await act(
    adaptador => adaptador.apagar(props.adId, deleting.value.id),
    'DELETE_DONE',
    'MANAGE_ERROR'
  );
  busy.value = false;
  deleteDialog.value?.close();
  deleting.value = null;
};

const tabCount = aba => {
  const count = unansweredCount(aba.key);
  return count ? t(`${KEY}.TAB_UNANSWERED`, { count }, count) : '';
};
</script>

<template>
  <div class="contents">
    <section
      v-if="loading || visible.length"
      data-ad-comments
      class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-4 ring-1 ring-inset ring-n-weak sm:p-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h4 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t(`${KEY}.TITLE`) }}
        </h4>
        <a
          v-if="result?.permalink_url"
          :href="result.permalink_url"
          target="_blank"
          rel="noopener noreferrer"
          data-ad-comments-open
          class="inline-flex min-h-11 items-center gap-1.5 rounded-xl text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        >
          {{ $t(`${KEY}.${current.key}.OPEN`) }}
          <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
        </a>
      </div>

      <div v-if="loading" class="flex justify-center py-6">
        <Spinner />
      </div>

      <template v-else>
        <div
          v-if="visible.length > 1"
          role="tablist"
          :aria-label="$t(`${KEY}.TITLE`)"
          data-ad-comments-tabs
          class="flex gap-1 self-start rounded-xl bg-n-alpha-1 p-1 max-sm:self-stretch"
        >
          <button
            v-for="(aba, index) in visible"
            :id="`ad-comments-tab-${aba.key}`"
            :key="aba.key"
            :ref="el => (tabRefs[index] = el)"
            type="button"
            role="tab"
            :data-ad-comments-tab="aba.key"
            :aria-selected="aba.key === current.key"
            :aria-controls="`ad-comments-panel-${aba.key}`"
            :tabindex="aba.key === current.key ? 0 : -1"
            class="inline-flex min-h-11 min-w-0 flex-1 flex-wrap items-center justify-center gap-x-2 rounded-lg border-0 px-3 py-1.5 text-center text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand sm:flex-none sm:flex-nowrap sm:whitespace-nowrap sm:px-4"
            :class="
              aba.key === current.key
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="select(index)"
            @keydown="onTabKey($event, index)"
          >
            <span class="inline-flex items-center gap-2">
              <span :class="ICONS[aba.key]" class="size-4" aria-hidden="true" />
              {{ $t(`${KEY}.${aba.key}.TAB`) }}
            </span>
            <span
              v-if="tabCount(aba)"
              data-ad-comments-tab-count
              class="text-xs font-normal text-n-slate-11"
            >
              {{ tabCount(aba) }}
            </span>
          </button>
        </div>

        <div
          :id="`ad-comments-panel-${current.key}`"
          role="tabpanel"
          :aria-labelledby="
            visible.length > 1 ? `ad-comments-tab-${current.key}` : undefined
          "
          class="flex flex-col gap-4"
        >
          <div
            v-if="failed[current.key]"
            data-ad-comments-error
            class="flex flex-col items-start gap-2"
          >
            <p class="m-0 text-sm text-n-slate-11">{{ $t(`${KEY}.ERROR`) }}</p>
            <button
              type="button"
              class="inline-flex min-h-11 items-center rounded-lg border-0 bg-n-alpha-2 px-4 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-3"
              @click="read(current)"
            >
              {{ $t(`${KEY}.RETRY`) }}
            </button>
          </div>

          <div
            v-else-if="blocked"
            :data-ad-comments-state="status"
            class="flex flex-col items-start gap-3 rounded-xl bg-n-alpha-1 p-4"
          >
            <p class="m-0 text-base font-semibold text-n-slate-12">
              {{ $t(`${statusKey}_TITLE`) }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ $t(statusKey, { username: result.account?.username }) }}
            </p>
            <p
              v-if="showAsk"
              data-ad-comments-ask
              class="m-0 text-sm text-n-slate-11"
            >
              {{ $t(`${statusKey}_ASK`) }}
            </p>
            <button
              v-if="showFix"
              type="button"
              :data-ad-comments-action="status"
              class="inline-flex min-h-11 items-center gap-2 whitespace-nowrap rounded-lg border-0 bg-n-brand px-4 text-sm font-medium text-white hover:bg-n-brand/90"
              @click="login(status)"
            >
              <span
                :class="ICONS[current.key]"
                class="size-4"
                aria-hidden="true"
              />
              {{ $t(`${statusKey}_BUTTON`) }}
            </button>
            <p
              v-if="showFix && $te(`${statusKey}_AFTER`)"
              class="m-0 text-sm text-n-slate-11"
            >
              {{ $t(`${statusKey}_AFTER`) }}
            </p>
          </div>

          <p
            v-else-if="!result?.comments?.length"
            data-ad-comments-empty
            class="m-0 text-sm text-n-slate-11"
          >
            {{ $t(`${KEY}.EMPTY`) }}
          </p>

          <template v-else>
            <p
              v-if="canManage && $te(`${KEY}.${current.key}.NOTE`)"
              data-ad-comments-note
              class="m-0 text-sm text-n-slate-11"
            >
              {{ $t(`${KEY}.${current.key}.NOTE`) }}
            </p>
            <ul class="m-0 flex flex-col gap-5 p-0" data-ad-comments-list>
              <MetaAdsCommentRow
                v-for="comment in comments"
                :key="comment.id"
                :comment="comment"
                :can-manage="canManage"
                :unknown-author-key="unknownAuthorKey"
                :acoes="acoes"
                :unanswered="isUnanswered(comment)"
              />
            </ul>
            <button
              v-if="canShowMore"
              type="button"
              data-ad-comments-more
              :disabled="loadingMore"
              class="inline-flex min-h-11 items-center self-start whitespace-nowrap rounded-lg border-0 bg-n-alpha-1 px-4 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
              @click="more"
            >
              {{ $t(`${KEY}.MORE`) }}
            </button>
          </template>
        </div>
      </template>

      <Dialog
        ref="deleteDialog"
        type="alert"
        :title="
          deleting
            ? $t(`${KEY}.DELETE_TITLE`, { name: authorName(deleting) })
            : ''
        "
        :description="
          deleting ? $t(`${KEY}.DELETE_HINT`, { text: quote(deleting) }) : ''
        "
        :confirm-button-label="$t(`${KEY}.DELETE_CONFIRM`)"
        :cancel-button-label="$t(`${KEY}.CANCEL`)"
        :is-loading="busy"
        @confirm="confirmDelete"
      />
    </section>
  </div>
</template>
