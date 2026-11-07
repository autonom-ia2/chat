<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { seloDe } from '../utils/acharChance';

// #2692 — o cartão grande da fila "Para chamar" (v4, T5): selo, nome, e três
// blocos — "Por que chamar", "Com quem falar" e "Como chamar". No pé, "Não serve"
// e "Depois" (só quem pode mexer). Em 390 o cartão fica p-5, sem sombra.
// Rodada 2: link "Ver mais sobre a empresa" (telefone, site, avaliações).
const props = defineProps({
  empresa: { type: Object, required: true },
  primeiro: { type: Boolean, default: false },
  achadoPor: { type: String, default: '' },
  podeDecidir: { type: Boolean, default: false },
});
const emit = defineEmits(['naoServe', 'depois', 'verMais']);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.FILA';
const selo = computed(() => seloDe(props.empresa.chance, props.primeiro));

const quemDecide = computed(() => {
  const { estado, nome, cargo } = props.empresa.dono;
  if (estado === 'procurando') {
    return {
      texto: t('PROSPECTING_ACHAR.CONFIRA.DONO.PROCURANDO'),
      girando: true,
    };
  }
  if (!nome) return { texto: t(`${NS}.SEM_DONO`) };
  // Rodada 3: o mesmo par da lista e da gaveta, sem selo de certeza.
  if (estado !== 'confirmado') return { texto: t(`${NS}.POSSIVEL`, { nome }) };
  return {
    texto: cargo
      ? t(`${NS}.DONO`, { nome, cargo })
      : t(`${NS}.DONO_SEM_CARGO`, { nome }),
  };
});

const comoChamar = computed(() => {
  const { whatsapp, telefone } = props.empresa;
  if (whatsapp === 'conferindo')
    return { texto: t(`${NS}.CONFERINDO`), girando: true };
  return {
    texto: t(whatsapp === 'tem' ? `${NS}.TEL_WHATS` : `${NS}.TEL_SO`, {
      telefone,
    }),
  };
});

const blocos = computed(() => [
  {
    id: 'porque',
    titulo: t(`${NS}.POR_QUE`),
    icone: 'i-lucide-lightbulb',
    tom: 'bg-n-amber-3 text-n-amber-11',
    texto: props.empresa.porque,
  },
  {
    id: 'dono',
    titulo: t(`${NS}.QUEM_DECIDE`),
    icone: 'i-lucide-user-round',
    tom: 'bg-n-blue-3 text-n-blue-11',
    ...quemDecide.value,
  },
  {
    id: 'como',
    titulo: t(`${NS}.COMO_CHAMAR`),
    icone: 'i-lucide-phone',
    tom: 'bg-n-teal-3 text-n-teal-11',
    ...comoChamar.value,
  },
]);
</script>

<template>
  <article
    class="flex flex-col gap-5 p-5 border rounded-3xl border-n-weak bg-n-solid-1 md:p-8 md:shadow-sm"
    data-cartao-fila
  >
    <div class="flex flex-wrap items-center gap-2">
      <span
        class="px-2.5 py-0.5 text-xs font-semibold rounded-full"
        :class="selo.classe"
      >
        {{ $t(selo.chave) }}
      </span>
      <span v-if="achadoPor" class="text-sm text-n-slate-11" data-achado-por>
        {{ $t(`${NS}.ACHADO_POR`, { pessoa: achadoPor }) }}
      </span>
    </div>
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-2xl font-bold break-words text-n-slate-12">
        {{ empresa.nome }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ [empresa.categoria, empresa.bairro].filter(Boolean).join(' · ') }}
      </p>
    </div>
    <ul class="flex flex-col gap-4 p-0 m-0 list-none">
      <li v-for="bloco in blocos" :key="bloco.id" class="flex gap-3">
        <span
          class="grid shrink-0 place-items-center rounded-2xl size-11"
          :class="bloco.tom"
          aria-hidden="true"
        >
          <span class="size-5" :class="bloco.icone" />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <span class="text-sm font-semibold text-n-slate-11">
            {{ bloco.titulo }}
          </span>
          <span class="flex items-center gap-2 text-base text-n-slate-12">
            <span
              v-if="bloco.girando"
              class="i-lucide-loader-circle size-4 animate-spin"
              aria-hidden="true"
            />
            {{ bloco.texto }}
          </span>
        </div>
      </li>
    </ul>
    <button
      type="button"
      class="flex items-center self-start gap-1 px-1 text-sm font-medium min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      data-ver-mais
      @click="emit('verMais')"
    >
      {{ $t(`${NS}.VER_MAIS`) }}
      <span
        class="i-lucide-chevron-right size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
    <div v-if="podeDecidir" class="grid grid-cols-2 gap-3">
      <Button
        :label="$t(`${NS}.NAO_SERVE`)"
        icon="i-lucide-x"
        slate
        faded
        class="!min-h-12 !rounded-xl !text-base"
        data-nao-serve
        @click="emit('naoServe')"
      />
      <Button
        :label="$t(`${NS}.DEPOIS`)"
        icon="i-lucide-clock"
        slate
        faded
        class="!min-h-12 !rounded-xl !text-base"
        data-depois
        @click="emit('depois')"
      />
    </div>
  </article>
</template>
