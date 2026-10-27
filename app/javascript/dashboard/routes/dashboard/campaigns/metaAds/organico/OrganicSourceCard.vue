<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { intlLocale } from '../metaAdsHelpers';
import OrganicTile from './OrganicTile.vue';
import OrganicShareBar from './OrganicShareBar.vue';
import OrganicPostList from './OrganicPostList.vue';

// Seus posts (#2199): um cartão por lugar (Página do Facebook ou Instagram). Em cima, a frase que responde a pergunta
// do dono (vale pagar? / estou chegando a gente nova?); depois quem mandou mensagem por ali, os quatro números com a
// comparação e os posts com mais curtidas e comentários. Sem permissão, sem conta ou sem post no período, o cartão
// vira uma frase e um botão.
const props = defineProps({
  source: { type: String, required: true },
  data: { type: Object, required: true },
  days: { type: Number, required: true },
  readOnly: { type: Boolean, default: false },
  // Botão de destaque deste cartão (só um por tela); o do outro cartão fica secundário.
  primary: { type: Boolean, default: true },
  // Número do passo quando os dois cartões pedem para liberar ("1. Libere sua Página").
  step: { type: Number, default: null },
  // As conversas deste lugar já estão no botão do topo: o link "Ver conversas" do cartão sairia repetido.
  main: { type: Boolean, default: false },
});

const emit = defineEmits(['connect', 'conversations']);

const { t, locale } = useI18n();
const KEY = 'META_ADS_ORGANIC';
const HISTORY_DAYS = 90;
const sourceKey = computed(() => `${KEY}.SOURCE.${props.source.toUpperCase()}`);
const isPage = computed(() => props.source === 'page');
const ready = computed(() => props.data.status === 'ok');
const statusKey = computed(
  () => `${sourceKey.value}.${props.data.status.toUpperCase()}`
);

const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);

const title = computed(() =>
  isPage.value
    ? props.data.name
    : props.data.username && `@${props.data.username}`
);

// Período sem post e sem ninguém que viu: uma frase e o caminho para postar, em vez de zeros que parecem defeito.
const quiet = computed(
  () => ready.value && !props.data.reach && !props.data.top_posts?.length
);

const blockedTitle = computed(() => {
  const text = t(`${statusKey.value}.TITLE`);
  return props.step ? t(`${KEY}.STEP`, { step: props.step, text }) : text;
});

// Instagram com menos de 100 seguidores: a Meta não conta os seguidores novos (follower_count). O total vem do perfil.
const followersExtra = computed(() =>
  props.data.new_followers === null
    ? t(`${KEY}.TILES.FOLLOWERS.SMALL_ACCOUNT`)
    : t(`${KEY}.TILES.FOLLOWERS.NEW`, {
        count: format(props.data.new_followers),
        days: props.days,
      })
);

// Instagram no período de 90 dias: a Meta só guarda 90 dias, então não há período anterior. Uma frase acima dos
// quadros diz por quê, uma vez só.
const noCompare = computed(() => !isPage.value && props.days === HISTORY_DAYS);

// Seguidores mostra o total de hoje, sem comparação: o que mudou no período já está na linha "+N".
const tiles = computed(() => {
  const previous = props.data.previous || {};
  return [
    {
      name: 'REACH',
      icon: 'i-lucide-users',
      value: props.data.reach,
      previous: previous.reach ?? null,
    },
    {
      name: 'VIEWS',
      icon: 'i-lucide-eye',
      value: props.data.views,
      previous: previous.views ?? null,
    },
    {
      name: 'INTERACTIONS',
      icon: 'i-lucide-heart',
      value: props.data.interactions,
      previous: previous.interactions ?? null,
    },
    {
      name: 'FOLLOWERS',
      icon: 'i-lucide-user-plus',
      value: props.data.followers,
      previous: null,
      extra: followersExtra.value,
    },
  ];
});

const share = computed(() =>
  isPage.value
    ? {
        textKey: 'ADS_SHARE',
        part: props.data.views - props.data.views_from_ads,
        total: props.data.views,
      }
    : {
        textKey: 'NEW_PEOPLE',
        part: props.data.reach_non_followers,
        total: props.data.reach,
        secondTone: 'slate',
      }
);

const messages = computed(() => props.data.messages);
// Contagem nula: a pessoa não vê as conversas desta caixa (o servidor conta só o que ela vê). Nunca vira "0".
const messagesText = computed(() =>
  messages.value.count === null
    ? t(`${KEY}.MESSAGES_NO_ACCESS`)
    : t(
        `${sourceKey.value}.MESSAGES`,
        { count: format(messages.value.count) },
        messages.value.count
      )
);

const openLink = () => window.open(props.data.link, '_blank', 'noopener');
</script>

<template>
  <article
    :data-organic-source="source"
    class="flex min-w-0 flex-col gap-5 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
  >
    <header class="flex items-center gap-3">
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl"
        :class="isPage ? 'bg-n-blue-9 text-white' : 'bg-n-alpha-1'"
        aria-hidden="true"
      >
        <span
          :class="isPage ? 'i-woot-facebook' : 'i-woot-instagram-color'"
          class="size-6"
        />
      </span>
      <div class="flex min-w-0 flex-col">
        <h3 class="m-0 truncate text-base font-semibold text-n-slate-12">
          {{ title || $t(`${sourceKey}.NAME`) }}
        </h3>
        <p v-if="title" class="m-0 text-sm text-n-slate-11">
          {{ $t(`${sourceKey}.NAME`) }}
        </p>
      </div>
      <a
        v-if="ready && !quiet && data.link"
        :href="data.link"
        target="_blank"
        rel="noopener noreferrer"
        class="ms-auto inline-flex min-h-11 shrink-0 items-center gap-1 rounded-lg px-2 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        {{ $t(`${sourceKey}.OPEN`) }}
        <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
      </a>
    </header>

    <div
      v-if="!ready"
      :data-organic-blocked="data.status"
      class="flex flex-col items-start gap-3 rounded-xl bg-n-alpha-1 p-5"
    >
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ blockedTitle }}
      </p>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t(`${statusKey}.TEXT`) }}
      </p>
      <Button
        v-if="!readOnly"
        :data-organic-connect="source"
        :variant="primary ? 'solid' : 'faded'"
        :color="primary ? 'blue' : 'slate'"
        :icon="isPage ? 'i-woot-facebook' : 'i-woot-instagram'"
        :label="$t(`${statusKey}.BUTTON`)"
        class="!min-h-11 !rounded-xl"
        @click="emit('connect', source)"
      />
      <p v-else class="m-0 text-sm text-n-slate-11">
        {{ $t(`${KEY}.ASK_ADMIN`) }}
      </p>
    </div>

    <div
      v-else-if="quiet"
      data-organic-quiet
      class="flex flex-col items-start gap-3 rounded-xl bg-n-alpha-1 p-5"
    >
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t(`${KEY}.QUIET.TITLE`, { days }) }}
      </p>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{
          $t(`${KEY}.QUIET.TEXT`, { followers: format(data.followers || 0) })
        }}
      </p>
      <Button
        v-if="data.link"
        :data-organic-post="source"
        :variant="primary ? 'solid' : 'faded'"
        :color="primary ? 'blue' : 'slate'"
        icon="i-lucide-external-link"
        :label="$t(`${sourceKey}.POST`)"
        class="!min-h-11 !rounded-xl"
        @click="openLink"
      />
    </div>

    <template v-else>
      <!-- Sem o recorte da Meta (part nulo), a barra some: "0% ainda não te segue" seria falso. -->
      <OrganicShareBar
        v-if="share.total && share.part != null"
        v-bind="share"
      />

      <div
        v-if="messages"
        data-organic-messages
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl p-4 ring-1 ring-inset ring-n-weak"
      >
        <p
          class="m-0 flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span
            class="i-lucide-message-circle size-5 shrink-0 text-n-teal-11"
            aria-hidden="true"
          />
          {{ messagesText }}
        </p>
        <Button
          v-if="messages.inbox_id && messages.count && !main"
          data-organic-see-conversations
          variant="link"
          :label="$t(`${sourceKey}.SEE_CONVERSATIONS`)"
          class="!min-h-11"
          @click="emit('conversations', messages.inbox_id)"
        />
      </div>

      <p
        v-if="noCompare"
        data-organic-no-compare
        class="m-0 -mb-2 text-sm text-n-slate-11"
      >
        {{ $t(`${KEY}.TILES.NO_COMPARE`) }}
      </p>
      <div class="grid grid-cols-1 gap-3 min-[420px]:grid-cols-2">
        <OrganicTile
          v-for="tile in tiles"
          :key="tile.name"
          :name="tile.name"
          :icon="tile.icon"
          :value="tile.value"
          :previous="tile.previous"
          :days="days"
          :extra="tile.extra"
        />
      </div>

      <OrganicPostList :posts="data.top_posts" :days="days" />
    </template>
  </article>
</template>
