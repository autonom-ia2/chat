<script setup>
// A conta sem nenhuma função (#2308): o herói e as 3 prontas em destaque, com o que cada uma faz. O herói usa
// o botão branco sobre navy da casa (Automações), a única exceção registrada na especificação (seção 9).
const emit = defineEmits(['criar']);

const ICONE_DO_TIPO = {
  pode: 'i-lucide-check text-n-teal-11',
  soOlha: 'i-lucide-eye text-n-slate-11',
};

const DESTAQUES = [
  {
    chave: 'ATENDENTE',
    icone: 'i-lucide-headset',
    tom: 'bg-n-blue-3 text-n-blue-11',
    capacidades: [
      { chave: 'CAP_1', tipo: 'pode' },
      { chave: 'CAP_2', tipo: 'pode' },
      { chave: 'CAP_3', tipo: 'soOlha' },
    ],
  },
  {
    chave: 'VENDEDOR',
    icone: 'i-lucide-handshake',
    tom: 'bg-n-teal-3 text-n-teal-11',
    capacidades: [
      { chave: 'CAP_1', tipo: 'pode' },
      { chave: 'CAP_2', tipo: 'pode' },
      { chave: 'CAP_3', tipo: 'pode' },
    ],
  },
  {
    chave: 'SUPERVISOR',
    icone: 'i-lucide-eye',
    tom: 'bg-n-amber-3 text-n-amber-11',
    capacidades: [
      { chave: 'CAP_1', tipo: 'pode' },
      { chave: 'CAP_2', tipo: 'pode' },
      { chave: 'CAP_3', tipo: 'pode' },
    ],
  },
];
</script>

<template>
  <div data-vazio class="flex flex-col gap-6">
    <section
      class="relative px-6 py-10 overflow-hidden text-white rounded-3xl bg-[#0D2344] md:px-12 md:py-12"
    >
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
      />
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
      />
      <div class="relative flex flex-col max-w-2xl gap-5">
        <p class="m-0 text-sm font-semibold text-n-blue-6">
          {{ $t('FUNCOES_EQUIPE.TITULO') }}
        </p>
        <h1
          class="m-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
        >
          {{ $t('FUNCOES_EQUIPE.VAZIO.TITULO') }}
        </h1>
        <p class="m-0 text-base md:text-lg text-white/80">
          {{ $t('FUNCOES_EQUIPE.VAZIO.TEXTO') }}
        </p>
        <button
          type="button"
          data-criar-primeira
          class="inline-flex items-center self-start gap-2 px-5 text-sm font-semibold bg-white rounded-xl min-h-11 text-[#0D2344] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
          @click="emit('criar')"
        >
          {{ $t('FUNCOES_EQUIPE.VAZIO.CRIAR') }}
          <span
            class="i-lucide-arrow-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </div>
    </section>

    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('FUNCOES_EQUIPE.VAZIO.DESTAQUE') }}
    </h2>
    <ul class="grid gap-4 p-0 m-0 list-none sm:grid-cols-3">
      <li v-for="pronta in DESTAQUES" :key="pronta.chave" class="flex">
        <button
          type="button"
          :data-pronta="pronta.chave"
          class="flex flex-col w-full gap-3 p-5 transition border shadow-sm text-start rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="
            $t('FUNCOES_EQUIPE.VAZIO.CRIAR_PRONTA', {
              nome: $t(`FUNCOES_EQUIPE.PRONTAS.${pronta.chave}.NOME`),
            })
          "
          @click="emit('criar')"
        >
          <span
            class="grid place-items-center size-11 rounded-xl"
            :class="pronta.tom"
          >
            <span class="size-5" :class="pronta.icone" aria-hidden="true" />
          </span>
          <span class="flex items-center gap-2">
            <span class="flex-1 text-lg font-semibold text-n-slate-12">
              {{ $t(`FUNCOES_EQUIPE.PRONTAS.${pronta.chave}.NOME`) }}
            </span>
            <span
              class="i-lucide-chevron-right size-5 text-n-slate-11 rtl:rotate-180"
              aria-hidden="true"
            />
          </span>
          <span class="text-[0.9375rem] leading-snug text-n-slate-11">
            {{ $t(`FUNCOES_EQUIPE.PRONTAS.${pronta.chave}.DESCRICAO`) }}
          </span>
          <span class="flex flex-col gap-1.5 text-[0.9375rem] text-n-slate-12">
            <span
              v-for="capacidade in pronta.capacidades"
              :key="capacidade.chave"
              :data-tipo="capacidade.tipo"
              class="flex items-start gap-2"
            >
              <span
                class="size-4 mt-1 shrink-0"
                :class="ICONE_DO_TIPO[capacidade.tipo]"
                aria-hidden="true"
              />
              {{
                $t(`FUNCOES_EQUIPE.PRONTAS.${pronta.chave}.${capacidade.chave}`)
              }}
            </span>
          </span>
        </button>
      </li>
    </ul>
  </div>
</template>
