<script setup>
import { SEM_LOGIN } from './anunciosSemLogin';

// Desenho da tela da Meta (#2054), não um print: mostra onde tocar, na ordem, com números. `partner` é a tela de
// Parceiros (Adicionar › acesso aos seus ativos › código); `assets` é a escolha da conta de anúncios com só
// "Ver desempenho" ligado. Os nomes dos botões seguem os da Meta em português.
defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['partner', 'assets'].includes(value),
  },
  partnerId: { type: String, default: '' },
});

const G = `${SEM_LOGIN}.CONNECT.GUIDE`;
// Endereço e números do desenho: não são texto a traduzir.
const META_HOST = 'business.facebook.com';
const STEP = [1, 2, 3];
</script>

<template>
  <figure
    :data-meta-tela-guia="kind"
    class="m-0 flex flex-col overflow-hidden rounded-2xl bg-n-slate-2 ring-1 ring-inset ring-n-weak"
    :aria-label="$t(`${G}.LABEL`)"
  >
    <div
      class="flex items-center gap-2 border-b border-solid border-n-weak bg-n-solid-1 px-4 py-2"
      aria-hidden="true"
    >
      <span class="size-2.5 rounded-full bg-n-slate-6" />
      <span class="size-2.5 rounded-full bg-n-slate-6" />
      <span class="size-2.5 rounded-full bg-n-slate-6" />
      <span class="ms-2 truncate text-xs text-n-slate-10">
        {{ META_HOST }}
      </span>
    </div>

    <div v-if="kind === 'partner'" class="flex flex-col gap-3 p-4 sm:p-5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ [$t(`${G}.SETTINGS`), $t(`${G}.PARTNERS`)].join(' › ') }}
      </span>
      <ol class="m-0 flex list-none flex-col gap-3 p-0">
        <li class="flex items-center gap-3">
          <span
            class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
          >
            {{ STEP[0] }}
          </span>
          <span
            class="inline-flex items-center gap-1.5 rounded-lg bg-n-blue-9 px-3 py-1.5 text-sm font-semibold text-white"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ $t(`${G}.ADD`) }}
          </span>
        </li>
        <li class="flex items-center gap-3">
          <span
            class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
          >
            {{ STEP[1] }}
          </span>
          <span
            class="rounded-lg bg-n-solid-1 px-3 py-1.5 text-sm text-n-slate-12 shadow-sm ring-2 ring-n-blue-7"
          >
            {{ $t(`${G}.GIVE_ACCESS`) }}
          </span>
        </li>
        <li class="flex flex-wrap items-center gap-3">
          <span
            class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
          >
            {{ STEP[2] }}
          </span>
          <span class="flex min-w-0 flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              $t(`${G}.PARTNER_ID`)
            }}</span>
            <span
              class="rounded-lg bg-n-solid-1 px-3 py-1.5 font-mono text-sm text-n-slate-12 ring-1 ring-inset ring-n-slate-7"
            >
              {{ partnerId }}
            </span>
          </span>
          <span class="text-xs text-n-slate-11">{{ $t(`${G}.PASTE`) }}</span>
        </li>
      </ol>
    </div>

    <div v-else class="flex flex-col gap-3 p-4 sm:p-5">
      <span class="text-xs font-medium text-n-slate-11">
        {{ $t(`${G}.AD_ACCOUNTS`) }}
      </span>
      <div class="flex flex-col gap-3 rounded-xl bg-n-solid-1 p-3 shadow-sm">
        <span class="flex items-center gap-3">
          <span
            class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
          >
            {{ STEP[0] }}
          </span>
          <span
            class="grid size-5 place-items-center rounded bg-n-blue-9 text-white"
          >
            <span class="i-lucide-check size-3.5" aria-hidden="true" />
          </span>
          <span class="text-sm font-semibold text-n-slate-12">
            {{ $t(`${G}.YOUR_ACCOUNT`) }}
          </span>
        </span>
        <span class="flex flex-wrap items-center gap-3 ps-10">
          <span class="text-sm text-n-slate-12">{{ $t(`${G}.VIEW`) }}</span>
          <span
            class="relative inline-flex h-5 w-9 items-center rounded-full bg-n-blue-9"
          >
            <span class="absolute end-0.5 size-4 rounded-full bg-white" />
          </span>
          <span
            class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
          >
            {{ STEP[1] }}
          </span>
        </span>
        <span class="flex items-center gap-3 ps-10 opacity-60">
          <span class="text-sm text-n-slate-11">{{ $t(`${G}.MANAGE`) }}</span>
          <span
            class="relative inline-flex h-5 w-9 items-center rounded-full bg-n-slate-6"
          >
            <span class="absolute start-0.5 size-4 rounded-full bg-white" />
          </span>
        </span>
      </div>
      <span class="flex items-center gap-3">
        <span
          class="grid size-7 flex-none place-items-center rounded-full bg-n-blue-9 text-xs font-bold text-white"
        >
          {{ STEP[2] }}
        </span>
        <span
          class="rounded-lg bg-n-blue-9 px-3 py-1.5 text-sm font-semibold text-white"
        >
          {{ $t(`${G}.SAVE`) }}
        </span>
      </span>
    </div>
    <figcaption class="px-4 pb-3 text-xs text-n-slate-10 sm:px-5">
      {{ $t(`${G}.CAPTION`) }}
    </figcaption>
  </figure>
</template>
