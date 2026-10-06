<script setup>
// Anúncios da Meta (#1047): estado vazio. Uma frase, o que a pessoa ganha e um botão.
defineEmits(['start']);

const BENEFITS = [
  { key: 'COST', icon: 'i-lucide-circle-dollar-sign' },
  { key: 'NAMES', icon: 'i-lucide-tag' },
  { key: 'SALES', icon: 'i-lucide-sparkles' },
];
</script>

<template>
  <section
    data-meta-ads-hero
    class="relative overflow-hidden rounded-3xl bg-[#0D2344] px-6 py-10 text-white md:px-12 md:py-12"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col max-w-3xl gap-5">
      <span
        class="inline-flex items-center gap-2 text-xs font-semibold tracking-wider uppercase text-n-blue-6"
      >
        <span class="i-lucide-megaphone size-4" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.EMPTY.EYEBROW') }}
      </span>
      <h2
        class="m-0 text-3xl font-semibold leading-tight text-white md:text-4xl text-balance"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.EMPTY.TITLE') }}
      </h2>
      <p class="max-w-2xl text-base text-white/75">
        {{ $t('CRM_KANBAN.META_ADS_HUB.EMPTY.DESCRIPTION') }}
      </p>
      <ul class="grid gap-3 p-0 m-0 list-none sm:grid-cols-3">
        <li
          v-for="benefit in BENEFITS"
          :key="benefit.key"
          class="flex flex-col gap-1 p-4 border rounded-2xl bg-white/5 border-white/10"
        >
          <span
            :class="benefit.icon"
            class="size-5 text-n-blue-6"
            aria-hidden="true"
          />
          <span class="text-sm font-semibold">
            {{ $t(`CRM_KANBAN.META_ADS_HUB.EMPTY.BENEFIT_${benefit.key}`) }}
          </span>
          <span class="text-sm text-white/75">
            {{
              $t(`CRM_KANBAN.META_ADS_HUB.EMPTY.BENEFIT_${benefit.key}_HINT`)
            }}
          </span>
        </li>
      </ul>
      <div>
        <button
          type="button"
          data-meta-ads-start
          class="inline-flex items-center gap-2 px-5 text-sm font-semibold transition-colors bg-white rounded-xl min-h-11 text-[#0D2344] hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
          @click="$emit('start')"
        >
          <span class="i-lucide-plug size-4" aria-hidden="true" />
          {{ $t('CRM_KANBAN.META_ADS_HUB.EMPTY.CTA') }}
        </button>
      </div>
    </div>
  </section>
</template>
