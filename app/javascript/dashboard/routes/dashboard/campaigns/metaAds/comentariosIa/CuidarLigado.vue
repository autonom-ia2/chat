<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { intlLocale } from '../metaAdsHelpers';
import { porRede } from './redes';

// Comentários que viram cliente (#2212): o post depois de ligado. O selo, o resultado (quem recebeu no privado e quem
// respondeu), "Esperando você" com o que a IA deixou com você, "Chegaram antes de você ligar" com o "Ler e mandar", e
// "Escondi" com o que ela escondeu, e "Pausar" com um toque, sem confirmação: pausar é seguro. "Mudar o que eu
// respondo" reabre os passos preenchidos, ligado ou pausado. Sem `canManage`, a tela mostra o estado e nenhum botão
// de escrita. No celular, "Ver na caixa" e "Pausar" ficam presos ao pé, ao lado do botão redondo do menu do painel.
const props = defineProps({
  // O Painel do servidor.
  data: { type: Object, required: true },
  // Aviso logo depois de ligar ('new') ou de pedir o "Ler e mandar" ('queued').
  started: { type: String, default: null },
  canManage: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits([
  'pause',
  'resume',
  'inbox',
  'reply',
  'read-old',
  'change',
]);

const { locale, t } = useI18n();
const KEY = 'META_ADS_COMMENTS_AI.ON';
const on = computed(() => props.data.care === 'on');
const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);
const handle = item =>
  item.network === 'facebook' ? item.author : `@${item.author}`;
// "Esperando você" sempre; "Escondi" só quando escondi algum. As perguntas que chegaram antes de ligar ficam num grupo
// próprio, com "Ler e mandar": quem disse "Agora não" depois de ligar ainda pode voltar atrás.
const BEFORE_KINDS = ['waiting', 'older', 'skipped'];
const toSee = computed(() => props.data.to_see || []);
const hidden = computed(() =>
  (props.data.hidden || []).map(item => ({ ...item, kind: 'hidden' }))
);
const before = computed(() =>
  props.data.para_quem
    ? toSee.value.filter(item => BEFORE_KINDS.includes(item.kind))
    : []
);
const groups = computed(() => [
  {
    key: 'waiting',
    title: 'TO_SEE',
    items: toSee.value.filter(item => !before.value.includes(item)),
  },
  ...(before.value.length
    ? [{ key: 'before', title: 'BEFORE', items: before.value, read: true }]
    : []),
  ...(hidden.value.length
    ? [{ key: 'hidden', title: 'HIDDEN', items: hidden.value }]
    : []),
]);
// "1 recebeu · 0 responderam": a forma de cada número escolhida aqui (1 = singular), sem depender da escolha de
// plural do vue-i18n, que pegava o singular para o 0.
const counts = computed(() => ({
  sent: Number(props.data.results?.sent) || 0,
  replied: Number(props.data.results?.replied) || 0,
}));
const results = computed(() => ({
  sent: format(counts.value.sent),
  replied: format(counts.value.replied),
}));
const one = (key, count) => (count === 1 ? `${key}_ONE` : key);
const resultLine = computed(
  () =>
    `${t(one(porRede(`${KEY}.RESULT`, props.data.network), counts.value.sent), results.value)} · ${t(one(`${KEY}.REPLIED`, counts.value.replied), results.value)}`
);
const startedText = computed(() => {
  if (props.started === 'queued') return t(`${KEY}.STARTED_OLD_QUEUED`);
  return props.data.para_quem
    ? t(`${KEY}.STARTED_DONO`, { who: props.data.para_quem })
    : t(`${KEY}.STARTED`);
});
</script>

<template>
  <section
    data-ia-on
    :data-ia-care="data.care"
    class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
  >
    <p
      v-if="started"
      role="status"
      data-ia-started
      class="m-0 flex items-start gap-2 rounded-xl bg-n-teal-3 px-4 py-3 text-sm font-medium text-n-teal-12"
    >
      <span class="i-lucide-check mt-0.5 size-4 shrink-0" aria-hidden="true" />
      {{ startedText }}
    </p>

    <span
      data-ia-badge
      class="inline-flex w-fit items-center gap-1.5 rounded-full px-3 py-1 text-sm font-semibold"
      :class="
        on ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-amber-3 text-n-amber-11'
      "
    >
      <span
        class="size-4"
        :class="on ? 'i-lucide-sparkles' : 'i-lucide-pause'"
        aria-hidden="true"
      />
      {{
        on
          ? $t('META_ADS_COMMENTS_AI.BADGE_ON')
          : $t('META_ADS_COMMENTS_AI.BADGE_PAUSED')
      }}
    </span>

    <p v-if="!on" class="m-0 text-base font-medium leading-6 text-n-slate-12">
      {{ $t(`${KEY}.PAUSED_TEXT`) }}
    </p>
    <div v-else-if="counts.sent" class="flex flex-col gap-1">
      <p
        data-ia-result
        class="m-0 text-2xl font-bold leading-tight tracking-tight text-n-slate-12 tabular-nums"
      >
        <!-- Singular e plural de cada número: "1 recebeu", "2 receberam", "1 respondeu". -->
        {{ resultLine }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ $t(`${KEY}.RESOLVED_HINT`) }}
      </p>
    </div>
    <p v-else class="m-0 text-base leading-6 text-n-slate-11">
      {{ $t(`${KEY}.NO_RESULT`) }}
    </p>

    <div
      data-ia-on-bar
      class="fixed inset-x-0 bottom-0 z-10 flex flex-nowrap items-center gap-2 border-0 border-t border-solid border-n-weak bg-n-solid-1 py-3 pe-4 ps-20 sm:static sm:border-0 sm:bg-transparent sm:p-0"
    >
      <Button
        v-if="!on && canManage"
        data-ia-resume
        icon="i-lucide-play"
        :label="$t(`${KEY}.RESUME`)"
        :is-loading="busy"
        class="!min-h-11 !rounded-xl !px-3"
        @click="emit('resume')"
      />
      <Button
        data-ia-inbox
        :variant="on ? 'solid' : 'faded'"
        :color="on ? 'blue' : 'slate'"
        icon="i-lucide-inbox"
        :label="$t(`${KEY}.INBOX`)"
        class="!min-h-11 !rounded-xl !px-3"
        @click="emit('inbox')"
      />
      <Button
        v-if="on && canManage"
        data-ia-pause
        variant="faded"
        color="slate"
        icon="i-lucide-pause"
        :label="$t(`${KEY}.PAUSE`)"
        :is-loading="busy"
        class="!min-h-11 !rounded-xl !px-3"
        @click="emit('pause')"
      />
    </div>

    <button
      v-if="canManage"
      type="button"
      data-ia-change
      class="inline-flex min-h-11 w-fit items-center gap-1.5 rounded-lg border-0 bg-transparent px-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('change')"
    >
      <span class="i-lucide-pencil size-4" aria-hidden="true" />
      {{ $t(`${KEY}.CHANGE`) }}
    </button>
  </section>

  <section
    v-for="group in groups"
    :key="group.key"
    :data-ia-to-see="group.key"
    class="flex flex-col gap-3 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{
          group.items.length
            ? $t(`${KEY}.${group.title}`, { count: group.items.length })
            : $t(`${KEY}.${group.title}_TITLE`)
        }}
      </h3>
      <Button
        v-if="group.read && canManage && data.unanswered && !data.read_old"
        data-ia-read-old
        icon="i-lucide-send"
        :label="$t(`${KEY}.READ_OLD`)"
        class="!min-h-11 w-full shrink-0 !rounded-xl sm:w-auto"
        @click="emit('read-old')"
      />
    </div>
    <p v-if="!group.items.length" class="m-0 text-sm text-n-slate-11">
      {{ $t(`${KEY}.TO_SEE_EMPTY`) }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="item in group.items"
        :key="item.id"
        :data-ia-to-see-row="item.kind"
        class="flex flex-col gap-3 rounded-xl p-4 ring-1 ring-inset ring-n-weak sm:flex-row sm:items-center"
      >
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <p class="m-0 text-base leading-6 text-n-slate-12">
            <span class="block text-sm font-semibold text-n-slate-11">
              {{ handle(item) }}
            </span>
            {{ item.text }}
          </p>
          <p
            class="m-0 text-sm"
            :class="
              item.kind === 'complaint' ? 'text-n-amber-11' : 'text-n-slate-11'
            "
          >
            {{ $t(`${KEY}.KIND.${item.kind}`) }}
          </p>
        </div>
        <Button
          v-if="item.kind !== 'hidden' && item.conversation_path"
          data-ia-open-inbox
          variant="faded"
          color="slate"
          icon="i-lucide-message-circle"
          :label="$t(`${KEY}.OPEN_INBOX`)"
          class="!min-h-11 shrink-0 !rounded-xl"
          @click="emit('inbox', item.conversation_path)"
        />
        <Button
          v-else-if="item.kind !== 'hidden'"
          data-ia-reply-comment
          variant="faded"
          color="slate"
          icon="i-lucide-image"
          :label="$t(`${KEY}.SEE_ON_POST`)"
          class="!min-h-11 shrink-0 !rounded-xl"
          @click="emit('reply')"
        />
      </li>
    </ul>
  </section>
</template>
