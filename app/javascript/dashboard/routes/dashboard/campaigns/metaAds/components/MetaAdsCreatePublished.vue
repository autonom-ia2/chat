<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { REDES, alvoDoImpulsionar } from '../criarPost';

// Anúncios da Meta (#2198 PR 3, #2653), criar post: publicado. Os links para ver o post em cada rede e o "Impulsionar
// este post", que segue com o post escolhido. Quando uma das redes não publicou, a frase diz qual e o botão tenta de
// novo só nela (com o vídeo ainda em preparo no Instagram, a frase diz para esperar um minuto). Vídeo da Página sozinho
// não oferece impulsionar: a Meta devolve só o vídeo, sem o post.
const props = defineProps({
  // { instagram: { id, permalink, boostable }, facebook: {...}, failed: ['instagram'], errors: { instagram: código } }
  published: { type: Object, required: true },
  retrying: { type: Boolean, default: false },
});

const emit = defineEmits(['boost', 'retry', 'done']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PUBLISHED';

const links = computed(() =>
  REDES.filter(rede => props.published[rede]?.permalink)
);
const canBoost = computed(() => Boolean(alvoDoImpulsionar(props.published)));
const PARTIAL_BY_ERROR = {
  processing: 'PROCESSING',
  unconfirmed: 'UNCONFIRMED',
};
const partialText = rede =>
  `${KEY}.${PARTIAL_BY_ERROR[props.published.errors?.[rede]] || 'PARTIAL'}.${rede.toUpperCase()}`;
// Sem saber se saiu, tentar de novo com a mesma chave não adianta: a pessoa confere na rede e diz que não saiu (o
// pai manda só esta rede, com chave nova).
const canRetry = rede => props.published.errors?.[rede] !== 'unconfirmed';
</script>

<template>
  <div data-create-published class="flex flex-col items-start gap-4">
    <div
      v-for="rede in published.failed || []"
      :key="rede"
      :data-create-published-partial="rede"
      role="status"
      class="flex w-full flex-col items-start gap-2 rounded-xl bg-n-amber-2 p-3 text-sm text-n-amber-12"
    >
      <p class="m-0 flex gap-2">
        <span
          class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(partialText(rede)) }}
      </p>
      <Button
        v-if="canRetry(rede)"
        :data-create-published-retry="rede"
        variant="faded"
        color="amber"
        :label="$t(`${KEY}.RETRY.${rede.toUpperCase()}`)"
        :is-loading="retrying"
        :disabled="retrying"
        @click="emit('retry', rede)"
      />
      <Button
        v-else
        :data-create-published-checked="rede"
        variant="faded"
        color="amber"
        :label="$t(`${KEY}.CHECKED.${rede.toUpperCase()}`)"
        :is-loading="retrying"
        :disabled="retrying"
        @click="emit('retry', rede, true)"
      />
    </div>
    <div v-if="links.length" class="flex flex-wrap gap-x-5 gap-y-1">
      <a
        v-for="rede in links"
        :key="rede"
        :href="published[rede].permalink"
        target="_blank"
        rel="noopener noreferrer"
        :data-create-published-link="rede"
        class="inline-flex min-h-11 items-center gap-1.5 text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      >
        {{ $t(`${KEY}.SEE.${rede.toUpperCase()}`) }}
        <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
      </a>
    </div>
    <template v-if="canBoost">
      <Button
        data-create-published-boost
        :label="$t(`${KEY}.BOOST`)"
        icon="i-lucide-rocket"
        class="w-full sm:w-auto"
        @click="emit('boost')"
      />
      <p class="m-0 text-sm text-n-slate-11">{{ $t(`${KEY}.BOOST_HINT`) }}</p>
    </template>
    <Button
      data-create-published-done
      variant="faded"
      color="slate"
      :label="$t(`${KEY}.DONE`)"
      class="w-full sm:w-auto"
      @click="emit('done')"
    />
  </div>
</template>
