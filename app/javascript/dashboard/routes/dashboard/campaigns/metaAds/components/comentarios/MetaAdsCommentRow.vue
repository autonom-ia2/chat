<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { relativeTime } from '../../metaAdsHelpers';

// Anúncios da Meta (#2196 Instagram, #2197 Facebook): um comentário do anúncio, com as respostas recuadas. As ações
// vêm dos dados (`can_reply`, `can_hide`, `can_delete`, `can_reply_private`), nunca da plataforma: a linha não sabe
// se é Instagram ou Facebook. Só aparecem para quem pode gerir (`canManage`). Apagar pede confirmação na casca.
// Privado enviado sem a Meta confirmar (rede caiu no meio): `private_reply.confirmed` false, e a linha diz isso. O
// botão não volta sozinho, porque a Meta pode ter entregado: quem gere confere no Direct e usa "Não foi enviado"
// (`private_reply.can_release`).
// Sem o privado porque passou de 7 dias (`private_reply_expired`), a linha diz isso. Quem não vê a caixa nem recebe a
// lista (#2358).
//
// Mensagem para o cliente só sai pelo botão: Enter quebra linha (no celular, a tecla de quebrar linha mandaria uma
// mensagem pela metade, e o privado só vai uma vez). Fechar a caixa guarda o rascunho; ele só some depois de enviar
// ou ao trocar entre resposta pública e privada.
//
// No celular, Ocultar e Apagar ficam no menu "Mais ações" (ícone no canto do cabeçalho), para Responder e Responder no
// privado caberem numa linha. Com uma ação só (a resposta da própria conta só se apaga), o botão aparece direto.
const props = defineProps({
  comment: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  unknownAuthorKey: { type: String, required: true },
  acoes: { type: Object, required: true },
  unanswered: { type: Boolean, default: false },
  isReply: { type: Boolean, default: false },
});

const { t, locale } = useI18n();

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.COMMENTS';

// Uma caixa de texto por vez: responder em público ou no privado.
const composer = ref(null);
const draftKind = ref(null);
const text = ref('');
const sending = ref(false);
const field = ref(null);
const menuOpen = ref(false);
const menu = ref(null);
const menuButton = ref(null);
const menuItems = ref([]);
const replyButton = ref(null);
const privateButton = ref(null);

onClickOutside(menu, () => {
  menuOpen.value = false;
});

const author = computed(() => props.comment.author || {});
const authorName = computed(() => {
  if (author.value.username) return `@${author.value.username}`;
  return author.value.name || t(props.unknownAuthorKey);
});
const initial = computed(() =>
  (author.value.username || author.value.name || '?').charAt(0).toUpperCase()
);
const when = computed(() =>
  relativeTime(props.comment.created_time, locale.value)
);
const privateSent = computed(() => props.comment.private_reply);
const canReply = computed(
  () => props.comment.can_reply && !props.comment.hidden
);
// Menu só faz sentido com as duas ações; com uma só, o botão fica à vista também no celular.
const useMenu = computed(
  () => props.comment.can_hide && props.comment.can_delete
);
const hasActions = computed(
  () =>
    canReply.value ||
    props.comment.can_reply_private ||
    props.comment.can_hide ||
    props.comment.can_delete
);

// Fechar devolve o foco ao botão que abriu a caixa (Esc, Cancelar ou depois de enviar).
const close = async () => {
  const opener = composer.value === 'private' ? privateButton : replyButton;
  composer.value = null;
  await nextTick();
  opener.value?.focus();
};

const open = async kind => {
  if (composer.value === kind) {
    close();
    return;
  }
  if (draftKind.value !== kind) text.value = '';
  draftKind.value = kind;
  composer.value = kind;
  await nextTick();
  field.value?.focus();
};

// Falha mantém a caixa aberta com o texto: a pessoa tenta de novo sem redigitar.
const send = async () => {
  const message = text.value.trim();
  if (!message || sending.value) return;
  sending.value = true;
  const ok =
    composer.value === 'private'
      ? await props.acoes.privado(props.comment, message)
      : await props.acoes.responder(props.comment, message);
  sending.value = false;
  if (!ok) return;
  text.value = '';
  close();
};

const focusItem = index => {
  const items = menuItems.value.filter(Boolean);
  if (!items.length) return;
  items[(index + items.length) % items.length].focus();
};

const toggleMenu = async () => {
  menuOpen.value = !menuOpen.value;
  if (!menuOpen.value) return;
  await nextTick();
  focusItem(0);
};

const closeMenu = () => {
  menuOpen.value = false;
  menuButton.value?.focus();
};

// Menu no padrão WAI-ARIA: setas percorrem os itens, Home e End vão às pontas, Esc fecha e devolve o foco.
const onMenuKey = event => {
  const items = menuItems.value.filter(Boolean);
  const current = items.indexOf(document.activeElement);
  const next = {
    ArrowDown: current + 1,
    ArrowUp: current - 1,
    Home: 0,
    End: items.length - 1,
  }[event.key];
  if (event.key === 'Escape') {
    event.preventDefault();
    closeMenu();
    return;
  }
  // Tab segue para o próximo elemento da página: o menu só fecha.
  if (event.key === 'Tab') {
    menuOpen.value = false;
    return;
  }
  if (next === undefined) return;
  event.preventDefault();
  focusItem(next);
};

const fromMenu = action => {
  closeMenu();
  action();
};

const hide = () => props.acoes.ocultar(props.comment, !props.comment.hidden);
const remove = () => props.acoes.apagar(props.comment);

const ACTION =
  'inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-transparent px-2.5 max-sm:gap-1 max-sm:px-1.5 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
const DANGER =
  'inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-transparent px-2.5 text-sm font-medium text-n-slate-11 hover:bg-n-ruby-9/10 hover:text-n-ruby-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-ruby-9';
</script>

<template>
  <li
    data-ad-comment
    :data-comment-id="comment.id"
    class="flex list-none flex-col gap-3"
    :class="{ 'pl-11': isReply }"
  >
    <div class="flex items-start gap-3">
      <span
        class="grid size-8 shrink-0 place-items-center rounded-full text-sm font-semibold"
        :class="
          author.is_page
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
        aria-hidden="true"
      >
        <span v-if="author.is_page" class="i-lucide-store size-4" />
        <template v-else>{{ initial }}</template>
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <div class="flex items-start gap-2">
          <p
            class="m-0 flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1 text-sm"
          >
            <span class="font-semibold text-n-slate-12">{{ authorName }}</span>
            <span
              v-if="author.is_page"
              data-ad-comment-page
              class="rounded-md bg-n-brand/10 px-1.5 text-xs font-medium text-n-blue-11"
            >
              {{ $t(`${KEY}.YOU`) }}
            </span>
            <span v-if="when" class="text-xs text-n-slate-11">{{ when }}</span>
            <span
              v-if="unanswered"
              data-ad-comment-unanswered
              class="rounded-md bg-n-amber-3 px-1.5 text-xs font-medium text-n-amber-11"
            >
              {{ $t(`${KEY}.UNANSWERED`) }}
            </span>
            <span
              v-if="comment.hidden"
              data-ad-comment-hidden
              class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-1.5 text-xs font-medium text-n-slate-11"
            >
              <span class="i-lucide-eye-off size-3" aria-hidden="true" />
              {{ $t(`${KEY}.HIDDEN`) }}
            </span>
          </p>
          <div
            v-if="canManage && useMenu"
            ref="menu"
            class="relative -my-2.5 -mr-2 shrink-0 sm:hidden"
          >
            <button
              ref="menuButton"
              type="button"
              data-ad-comment-more
              :aria-label="$t(`${KEY}.MORE_ACTIONS`)"
              :title="$t(`${KEY}.MORE_ACTIONS`)"
              :aria-expanded="menuOpen"
              aria-haspopup="menu"
              class="grid size-11 place-items-center rounded-lg border-0 bg-transparent text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              @click="toggleMenu"
            >
              <span class="i-lucide-ellipsis size-4" aria-hidden="true" />
            </button>
            <div
              v-if="menuOpen"
              role="menu"
              data-ad-comment-menu
              :aria-label="$t(`${KEY}.MORE_ACTIONS`)"
              class="absolute right-0 top-full z-10 mt-1 flex min-w-44 flex-col rounded-xl bg-n-solid-2 p-1 shadow-lg ring-1 ring-n-weak"
              @keydown="onMenuKey"
            >
              <button
                :ref="el => (menuItems[0] = el)"
                type="button"
                role="menuitem"
                tabindex="-1"
                data-ad-comment-menu-hide
                :class="ACTION"
                @click="fromMenu(hide)"
              >
                <span
                  :class="comment.hidden ? 'i-lucide-eye' : 'i-lucide-eye-off'"
                  class="size-4"
                  aria-hidden="true"
                />
                {{ $t(`${KEY}.${comment.hidden ? 'SHOW' : 'HIDE'}`) }}
              </button>
              <button
                :ref="el => (menuItems[1] = el)"
                type="button"
                role="menuitem"
                tabindex="-1"
                data-ad-comment-menu-delete
                :class="DANGER"
                @click="fromMenu(remove)"
              >
                <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
                {{ $t(`${KEY}.DELETE`) }}
              </button>
            </div>
          </div>
        </div>
        <p
          v-if="comment.text"
          class="m-0 whitespace-pre-line break-words text-sm leading-relaxed"
          :class="comment.hidden ? 'text-n-slate-11' : 'text-n-slate-12'"
        >
          {{ comment.text }}
        </p>
        <p
          v-else-if="comment.attachment"
          data-ad-comment-attachment
          class="m-0 inline-flex items-center gap-1.5 text-sm italic text-n-slate-11"
        >
          <span class="i-lucide-image size-3.5" aria-hidden="true" />
          {{
            $t(
              `${KEY}.${comment.attachment === 'photo' ? 'ATTACHMENT_PHOTO' : 'ATTACHMENT'}`
            )
          }}
        </p>
        <p
          v-if="privateSent"
          data-ad-comment-private-sent
          class="m-0 inline-flex flex-wrap items-center gap-x-2 text-sm text-n-slate-11"
        >
          <span class="i-lucide-send size-3.5" aria-hidden="true" />
          {{
            $t(
              privateSent.confirmed === false
                ? `${KEY}.PRIVATE_UNCONFIRMED`
                : `${KEY}.PRIVATE_SENT`
            )
          }}
          <router-link
            v-if="privateSent.conversation_path"
            :to="privateSent.conversation_path"
            class="-my-3 inline-flex min-h-11 items-center font-medium text-n-blue-11 no-underline hover:underline"
          >
            {{ $t(`${KEY}.OPEN_CONVERSATION`) }}
          </router-link>
          <button
            v-if="canManage && privateSent.can_release"
            type="button"
            data-ad-comment-private-release
            class="-my-3 inline-flex min-h-11 items-center border-0 bg-transparent p-0 font-medium text-n-blue-11 hover:underline"
            @click="acoes.liberar(comment)"
          >
            {{ $t(`${KEY}.PRIVATE_NOT_SENT`) }}
          </button>
        </p>
        <p
          v-else-if="canManage && comment.private_reply_expired"
          data-ad-comment-private-expired
          class="m-0 text-sm text-n-slate-11"
        >
          {{ $t(`${KEY}.PRIVATE_EXPIRED`) }}
        </p>
        <div
          v-if="canManage && hasActions"
          data-ad-comment-actions
          class="-ml-2.5 flex flex-wrap items-center"
        >
          <button
            v-if="canReply"
            ref="replyButton"
            type="button"
            data-ad-comment-reply
            :class="ACTION"
            :aria-expanded="composer === 'public'"
            @click="open('public')"
          >
            <span class="i-lucide-reply size-4" aria-hidden="true" />
            {{ $t(`${KEY}.REPLY`) }}
          </button>
          <button
            v-if="comment.can_reply_private"
            ref="privateButton"
            type="button"
            data-ad-comment-private
            :class="ACTION"
            :aria-expanded="composer === 'private'"
            @click="open('private')"
          >
            <span class="i-lucide-send size-4" aria-hidden="true" />
            {{ $t(`${KEY}.REPLY_PRIVATE`) }}
          </button>
          <button
            v-if="comment.can_hide"
            type="button"
            data-ad-comment-hide
            :class="[ACTION, { 'max-sm:hidden': useMenu }]"
            @click="hide"
          >
            <span
              :class="comment.hidden ? 'i-lucide-eye' : 'i-lucide-eye-off'"
              class="size-4"
              aria-hidden="true"
            />
            {{ $t(`${KEY}.${comment.hidden ? 'SHOW' : 'HIDE'}`) }}
          </button>
          <button
            v-if="comment.can_delete"
            type="button"
            data-ad-comment-delete
            :class="[DANGER, { 'max-sm:hidden': useMenu }]"
            @click="remove"
          >
            <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
            {{ $t(`${KEY}.DELETE`) }}
          </button>
        </div>
        <form
          v-if="composer"
          data-ad-comment-composer
          :data-kind="composer"
          class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3"
          @submit.prevent="send"
        >
          <label
            :for="`comment-${comment.id}-${composer}`"
            class="text-sm text-n-slate-11"
          >
            {{
              composer === 'private'
                ? $t(`${KEY}.PRIVATE_HINT`, { name: authorName })
                : $t(`${KEY}.REPLY_HINT`, { name: authorName })
            }}
          </label>
          <textarea
            :id="`comment-${comment.id}-${composer}`"
            ref="field"
            v-model="text"
            rows="3"
            maxlength="1000"
            class="mb-0 h-auto min-h-24 w-full resize-y rounded-lg border-0 bg-n-solid-1 p-2.5 text-sm text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand"
            @keydown.esc="close"
          />
          <div class="flex flex-wrap items-center justify-end gap-2">
            <button
              type="button"
              class="inline-flex min-h-11 items-center rounded-lg border-0 bg-transparent px-3 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
              @click="close"
            >
              {{ $t(`${KEY}.CANCEL`) }}
            </button>
            <button
              type="submit"
              data-ad-comment-send
              :disabled="!text.trim() || sending"
              class="inline-flex min-h-11 items-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-n-brand px-4 text-sm font-medium text-white hover:bg-n-brand/90 disabled:opacity-50"
            >
              <span
                class="i-lucide-send-horizontal size-4"
                aria-hidden="true"
              />
              {{
                composer === 'private'
                  ? $t(`${KEY}.SEND_PRIVATE`)
                  : $t(`${KEY}.SEND`)
              }}
            </button>
          </div>
        </form>
      </div>
    </div>
    <ul v-if="comment.replies?.length" class="m-0 flex flex-col gap-3 p-0">
      <MetaAdsCommentRow
        v-for="reply in comment.replies"
        :key="reply.id"
        :comment="reply"
        :can-manage="canManage"
        :unknown-author-key="unknownAuthorKey"
        :acoes="acoes"
        is-reply
      />
    </ul>
  </li>
</template>
