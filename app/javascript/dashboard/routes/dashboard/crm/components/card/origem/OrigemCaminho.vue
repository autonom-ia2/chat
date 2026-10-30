<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  buildCrmOrigin,
  CRM_ORIGIN_MAX_TOUCHES,
} from '../../../composables/useCrmOrigin';
import { useOrigemLeiga } from '../useOrigemLeiga';

// #1423 — o caminho do cliente até aqui, do primeiro ao último contato
// (VC-03), ou o único (VC-04). Mesmos dados da CrmOriginList, em palavras
// simples: por onde veio, o nome do anúncio, campanha, grupo e anúncio, a
// data e "Ver o anúncio" (abre em outra aba).
const props = defineProps({
  campanhas: { type: Array, default: () => [] },
});
const { t } = useI18n();
const leiga = useOrigemLeiga();
const miniaturasQuebradas = ref(new Set());

const linhas = computed(() => {
  const origens = props.campanhas
    .map(buildCrmOrigin)
    .filter(Boolean)
    .slice(0, CRM_ORIGIN_MAX_TOUCHES);
  const ultima = origens.length - 1;
  return origens.map((origem, indice) => {
    let marca = '';
    if (ultima > 0 && indice === 0) marca = t('CRM_CARD.ORIGEM.PRIMEIRO');
    else if (ultima > 0 && indice === ultima)
      marca = t('CRM_CARD.ORIGEM.ULTIMO');
    return {
      chave: `${indice}-${origem.sourceId || origem.headline}`,
      origem,
      fonte: leiga.titulo(origem),
      nome: leiga.nome(origem),
      data: leiga.data(origem),
      niveis: leiga.niveis(origem),
      link: leiga.link(origem),
      marca,
      ultima: indice === ultima,
    };
  });
});
</script>

<template>
  <ol
    class="m-0 flex list-none flex-col p-0"
    data-origem-caminho
    :data-toques="linhas.length"
  >
    <li
      v-for="linha in linhas"
      :key="linha.chave"
      class="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-3"
      data-crm-origin-touch
    >
      <span aria-hidden="true" class="relative flex justify-center">
        <span
          class="relative z-[1] grid size-10 place-items-center rounded-2xl bg-n-teal-3 text-n-teal-11"
        >
          <span :class="linha.origem.icon" class="size-5" />
        </span>
        <span
          v-if="!linha.ultima"
          class="absolute inset-y-0 top-11 w-px bg-n-strong"
        />
      </span>
      <div
        class="flex min-w-0 flex-col gap-1"
        :class="{ 'pb-5': !linha.ultima }"
      >
        <div
          class="flex min-w-0 flex-wrap items-baseline justify-between gap-x-3"
        >
          <p
            class="mb-0 min-w-0 text-[0.9375rem] font-semibold text-n-slate-12"
          >
            {{ linha.fonte }}
          </p>
          <time
            v-if="linha.data"
            :datetime="linha.data.iso"
            :title="linha.data.title"
            class="shrink-0 text-sm tabular-nums text-n-slate-11"
          >
            {{ linha.data.label }}
          </time>
        </div>
        <p v-if="linha.marca" class="mb-0 text-sm text-n-slate-11">
          {{ linha.marca }}
        </p>
        <p
          v-if="linha.nome"
          class="mb-0 break-words text-[0.9375rem] text-n-slate-12"
        >
          <q>{{ linha.nome }}</q>
        </p>
        <p
          v-if="linha.origem.adHidden"
          class="mb-0 text-sm text-n-slate-11"
          data-crm-origin-ad-hidden
        >
          {{ t('CRM_CARD.ORIGEM.ANUNCIO_OCULTO') }}
        </p>
        <dl
          v-if="linha.niveis.length"
          class="m-0 mt-1 grid grid-cols-[minmax(0,8rem)_minmax(0,1fr)] gap-x-3 gap-y-1 text-sm"
        >
          <template v-for="nivel in linha.niveis" :key="nivel.field">
            <dt class="text-n-slate-11">{{ nivel.level }}</dt>
            <dd
              class="m-0 min-w-0 break-words text-n-slate-12"
              :title="nivel.title"
              :data-crm-origin-level="nivel.field"
            >
              {{ nivel.value }}
            </dd>
          </template>
        </dl>
        <a
          v-if="linha.origem.adPreviewUrl"
          data-crm-origin-ad-preview
          :href="linha.origem.adPreviewUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="mt-1 flex min-h-11 w-fit max-w-full items-center gap-2.5 rounded-xl border border-n-weak p-1.5 pe-3 text-sm font-medium text-n-blue-11 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        >
          <img
            v-if="
              linha.origem.adThumbnailUrl &&
              !miniaturasQuebradas.has(linha.chave)
            "
            :src="linha.origem.adThumbnailUrl"
            alt=""
            class="size-8 shrink-0 rounded-lg object-cover"
            loading="lazy"
            referrerpolicy="no-referrer"
            @error="
              miniaturasQuebradas = new Set([
                ...miniaturasQuebradas,
                linha.chave,
              ])
            "
          />
          <span
            v-else
            class="i-lucide-image size-4 shrink-0 text-n-slate-10"
            aria-hidden="true"
          />
          <span class="truncate">{{ t('CRM_CARD.ORIGEM.VER_ANUNCIO') }}</span>
          <span
            class="i-lucide-arrow-up-right size-3.5 shrink-0"
            aria-hidden="true"
          />
          <span class="sr-only">{{ t('CRM_CARD.ORIGEM.OUTRA_ABA') }}</span>
        </a>
        <a
          v-else-if="linha.origem.sourceUrl && linha.link"
          :href="linha.origem.sourceUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex min-h-11 w-fit max-w-full items-center gap-1 rounded-lg text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :title="linha.origem.sourceUrl"
        >
          <span class="truncate">{{ linha.link }}</span>
          <span
            class="i-lucide-arrow-up-right size-3.5 shrink-0"
            aria-hidden="true"
          />
          <span class="sr-only">{{ t('CRM_CARD.ORIGEM.OUTRA_ABA') }}</span>
        </a>
      </div>
    </li>
  </ol>
</template>
