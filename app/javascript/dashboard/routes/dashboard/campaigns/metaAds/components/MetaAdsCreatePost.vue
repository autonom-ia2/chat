<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { longDate } from '../dinheiroDoAnuncio';

// Anúncios da Meta (#2198 PR 2, #2339), impulsionar: qual post. Abas Instagram e Facebook (a do Instagram só com
// conta ligada à Página). Post que a Meta não deixa impulsionar aparece apagado, com o motivo quando há: foto de
// perfil ou de capa da Página (`profile_or_cover`); no resto, a Meta não diz. Post do Instagram leva o botão de
// WhatsApp quando a conta tem número; post da Página leva ao post.
const props = defineProps({
  // Posts da Página: { id, message, created_time, image_url, reactions, comments, eligible, reason }.
  posts: { type: Array, default: () => [] },
  // Mídias do Instagram: { id, caption, timestamp, image_url, likes, comments, eligible, reason }.
  instagramPosts: { type: Array, default: () => [] },
  hasInstagram: { type: Boolean, default: false },
  hasNumber: { type: Boolean, default: true },
  loading: { type: Boolean, default: false },
  // O servidor não conseguiu ler os posts: a tela diz isso, nunca "sem posts".
  failed: { type: Boolean, default: false },
});

const emit = defineEmits(['retry']);

const draft = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const { currentAccount } = useAccount();

// O dia em que o post saiu, no fuso da conta: o horário da Meta vem em UTC, e um post das 22h não pode virar o dia seguinte.
const postDate = iso => {
  if (!iso) return null;
  const day = new Intl.DateTimeFormat('en-CA', {
    timeZone: fusoDaConta(currentAccount.value),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(iso));
  return longDate(day, locale.value);
};
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.POST';

const SOURCES = computed(() =>
  props.hasInstagram ? ['instagram', 'facebook'] : ['facebook']
);

const reasonText = post => {
  if (post.eligible) return '';
  return post.reason
    ? t(`${KEY}.REASONS.${post.reason.toUpperCase()}`)
    : t(`${KEY}.NOT_ELIGIBLE`);
};

// Os dois tipos de post no mesmo formato: { id, text, image_url, date, numbers, eligible, reason }.
const list = computed(() =>
  draft.value.post_source === 'instagram'
    ? props.instagramPosts.map(post => ({
        id: post.id,
        text: post.caption,
        image_url: post.image_url,
        date: post.timestamp,
        numbers: { likes: post.likes, comments: post.comments },
        eligible: post.eligible,
        reason: reasonText(post),
      }))
    : props.posts.map(post => ({
        id: post.id,
        text: post.message,
        image_url: post.image_url,
        date: post.created_time,
        numbers: { likes: post.reactions, comments: post.comments },
        eligible: post.eligible,
        reason: reasonText(post),
      }))
);

const setSource = source => {
  if (draft.value.post_source === source) return;
  draft.value = { ...draft.value, post_source: source, post_id: null };
};

const choose = post => {
  if (!post.eligible) return;
  draft.value = { ...draft.value, post_id: post.id };
};

// Cartões no padrão WAI-ARIA de grupo de rádio: só um entra no Tab (o escolhido, ou o primeiro que pode), e as setas
// escolhem o próximo que pode, levando o foco junto.
const grid = ref(null);
const eligible = computed(() => list.value.filter(post => post.eligible));
const focusable = computed(
  () =>
    eligible.value.find(post => post.id === draft.value.post_id)?.id ||
    eligible.value[0]?.id ||
    list.value[0]?.id
);
const moveChoice = async (post, delta) => {
  const cards = list.value;
  if (!eligible.value.length) return;
  // Anda a partir do cartão em foco (mesmo apagado), pulando os que não podem.
  let index = cards.findIndex(item => item.id === post.id);
  let target;
  do {
    index = (index + delta + cards.length) % cards.length;
    target = cards[index];
  } while (!target.eligible);
  choose(target);
  await nextTick();
  grid.value?.querySelector(`[data-create-post="${target.id}"]`)?.focus();
};

const tapNote = computed(() => {
  if (draft.value.post_source === 'facebook') return 'TAP_FACEBOOK';
  return props.hasNumber ? 'TAP_INSTAGRAM_WHATSAPP' : 'TAP_INSTAGRAM';
});

// Abas no padrão WAI-ARIA: ←/→ trocam e levam o foco junto.
const tabs = ref([]);
const move = async step => {
  const sources = SOURCES.value;
  const index =
    (sources.indexOf(draft.value.post_source) + step + sources.length) %
    sources.length;
  setSource(sources[index]);
  await nextTick();
  tabs.value[index]?.focus();
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4">
    <div
      v-if="loading"
      data-create-post-loading
      role="status"
      :aria-label="$t(`${KEY}.LOADING`)"
      class="flex justify-center p-8"
    >
      <Spinner />
    </div>

    <div
      v-else-if="failed"
      data-create-post-failed
      role="alert"
      class="flex flex-col items-start gap-3 rounded-xl bg-n-ruby-2 p-4"
    >
      <p class="m-0 flex gap-2 text-sm text-n-ruby-12">
        <span
          class="i-lucide-cloud-off mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.LOAD_FAILED`) }}
      </p>
      <Button
        data-create-post-retry
        outline
        :label="$t(`${KEY}.RETRY`)"
        @click="emit('retry')"
      />
    </div>

    <template v-else>
      <div
        v-if="SOURCES.length > 1"
        role="tablist"
        :aria-label="$t(`${KEY}.TITLE`)"
        class="flex gap-1 self-start rounded-xl bg-n-alpha-2 p-1"
      >
        <button
          v-for="source in SOURCES"
          :key="source"
          ref="tabs"
          type="button"
          role="tab"
          :data-create-post-source="source"
          :aria-selected="draft.post_source === source"
          aria-controls="posts-para-impulsionar"
          :tabindex="draft.post_source === source ? 0 : -1"
          class="inline-flex min-h-11 items-center gap-2 rounded-lg border-0 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            draft.post_source === source
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setSource(source)"
          @keydown.right.prevent="move(1)"
          @keydown.left.prevent="move(-1)"
        >
          <span
            :class="
              source === 'instagram'
                ? 'i-ri-instagram-line'
                : 'i-ri-facebook-circle-line'
            "
            class="size-4"
            aria-hidden="true"
          />
          {{ $t(`${KEY}.SOURCES.${source.toUpperCase()}`) }}
        </button>
      </div>

      <div
        id="posts-para-impulsionar"
        :role="SOURCES.length > 1 ? 'tabpanel' : undefined"
        class="flex min-w-0 flex-col gap-3"
      >
        <!-- O que acontece com quem toca, antes da lista: no celular, depois dela ficava escondido. -->
        <p data-create-post-tap class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.${tapNote}`) }}
        </p>
        <p
          v-if="!list.length"
          data-create-post-empty
          class="m-0 text-sm text-n-slate-11"
        >
          {{ $t(`${KEY}.EMPTY_SOURCE`) }}
        </p>
        <div
          v-else
          ref="grid"
          class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3"
          role="radiogroup"
          :aria-label="$t(`${KEY}.TITLE`)"
        >
          <button
            v-for="post in list"
            :key="post.id"
            type="button"
            role="radio"
            :aria-checked="draft.post_id === post.id"
            :aria-disabled="!post.eligible || undefined"
            :data-create-post="post.id"
            :tabindex="post.id === focusable ? 0 : -1"
            class="flex min-w-0 flex-col overflow-hidden rounded-2xl border-0 p-0 text-start transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="[
              draft.post_id === post.id
                ? 'bg-n-brand/10 ring-2 ring-n-brand'
                : 'bg-n-solid-1 ring-1 ring-n-weak hover:ring-n-strong',
              post.eligible ? '' : 'cursor-not-allowed',
            ]"
            @click="choose(post)"
            @keydown.right.prevent="moveChoice(post, 1)"
            @keydown.down.prevent="moveChoice(post, 1)"
            @keydown.left.prevent="moveChoice(post, -1)"
            @keydown.up.prevent="moveChoice(post, -1)"
          >
            <img
              v-if="post.image_url"
              :src="post.image_url"
              alt=""
              class="aspect-[4/3] w-full object-cover"
              :class="post.eligible ? '' : 'opacity-50 grayscale'"
            />
            <span class="flex flex-col gap-2 p-4">
              <span class="text-xs text-n-slate-10">
                {{ postDate(post.date) }}
              </span>
              <span class="line-clamp-3 text-sm text-n-slate-12">
                {{ post.text }}
              </span>
              <span v-if="post.eligible" class="text-xs text-n-slate-11">
                {{ $t(`${KEY}.NUMBERS`, post.numbers) }}
              </span>
              <span
                v-else
                data-create-post-not-eligible
                class="flex gap-1.5 text-xs font-medium text-n-amber-11"
              >
                <span
                  class="i-lucide-ban mt-0.5 size-3.5 shrink-0"
                  aria-hidden="true"
                />
                {{ post.reason }}
              </span>
            </span>
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
