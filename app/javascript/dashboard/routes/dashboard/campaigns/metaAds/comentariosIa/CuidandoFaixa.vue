<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { intlLocale } from '../metaAdsHelpers';
import { porRede } from './redes';

// Comentários que viram cliente (#2212): a faixa no topo de "Seus posts", "Cuidando dos comentários de 3 posts". Abre
// a lista desses posts (cada um leva à tela dele) e tem "Pausar todos", com um toque, como o "Pausar" de cada post.
const props = defineProps({
  posts: { type: Array, required: true },
  // Pausar e retomar todos: só quem pode mudar (posts_manage). Ver a lista é de todos.
  canManage: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['open', 'pause-all', 'resume-all']);

const { locale } = useI18n();
const KEY = 'META_ADS_COMMENTS_AI';
const open = ref(false);

const active = computed(() => props.posts.filter(post => post.status === 'on'));
const paused = computed(() =>
  props.posts.filter(post => post.status === 'paused')
);
const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);
</script>

<template>
  <section
    data-ia-band
    class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-4 ring-1 ring-inset ring-n-weak sm:p-5"
  >
    <div class="flex flex-wrap items-center gap-3">
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl"
        :class="
          active.length
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
        aria-hidden="true"
      >
        <span
          class="size-5"
          :class="active.length ? 'i-lucide-sparkles' : 'i-lucide-pause'"
        />
      </span>
      <div class="flex min-w-0 flex-1 flex-col">
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{
            active.length
              ? $t(`${KEY}.BAND.TITLE`, { count: active.length }, active.length)
              : $t(
                  `${KEY}.BAND.PAUSED`,
                  { count: paused.length },
                  paused.length
                )
          }}
        </p>
        <p
          v-if="active.length && paused.length"
          class="m-0 text-sm text-n-slate-11"
        >
          {{
            $t(`${KEY}.BAND.PAUSED`, { count: paused.length }, paused.length)
          }}
        </p>
      </div>
      <div class="flex w-full flex-wrap gap-2 sm:w-auto">
        <Button
          data-ia-band-toggle
          variant="faded"
          color="slate"
          :icon="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          :label="$t(`${KEY}.BAND.${open ? 'HIDE' : 'SHOW'}`)"
          :aria-expanded="open"
          aria-controls="ia-band-list"
          class="!min-h-11 !rounded-xl"
          @click="open = !open"
        />
        <Button
          v-if="canManage && active.length"
          data-ia-pause-all
          variant="faded"
          color="slate"
          icon="i-lucide-pause"
          :label="$t(`${KEY}.BAND.PAUSE_ALL`)"
          :is-loading="busy"
          class="!min-h-11 !rounded-xl"
          @click="emit('pause-all')"
        />
        <Button
          v-else-if="canManage"
          data-ia-resume-all
          icon="i-lucide-play"
          :label="$t(`${KEY}.BAND.RESUME_ALL`)"
          :is-loading="busy"
          class="!min-h-11 !rounded-xl"
          @click="emit('resume-all')"
        />
      </div>
    </div>

    <ul
      v-if="open"
      id="ia-band-list"
      :aria-label="$t(`${KEY}.BAND.LIST_LABEL`)"
      class="m-0 flex list-none flex-col gap-1 p-0"
    >
      <li v-for="post in posts" :key="post.id">
        <button
          type="button"
          :data-ia-band-post="post.id"
          class="flex min-h-11 w-full items-center gap-3 rounded-xl border-0 bg-transparent p-2 text-start hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="emit('open', post.id)"
        >
          <img
            v-if="post.image_url"
            :src="post.image_url"
            alt=""
            class="size-12 shrink-0 rounded-lg object-cover"
          />
          <span
            v-else
            class="size-12 shrink-0 rounded-lg bg-n-alpha-2"
            aria-hidden="true"
          />
          <span class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="line-clamp-1 text-sm text-n-slate-12">
              {{ post.text }}
            </span>
            <span
              class="text-sm"
              :class="
                post.status === 'on' ? 'text-n-slate-11' : 'text-n-amber-11'
              "
            >
              {{
                post.status === 'on'
                  ? $t(porRede(`${KEY}.BAND.RESULT`, post.network), {
                      sent: format(post.results.sent),
                      replied: format(post.results.replied),
                    })
                  : $t(`${KEY}.BADGE_PAUSED`)
              }}
            </span>
          </span>
          <span
            class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-11 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
  </section>
</template>
