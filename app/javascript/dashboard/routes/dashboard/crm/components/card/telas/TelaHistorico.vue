<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// #1423 — tudo o que já aconteceu com o card, por dia (Hoje, Ontem, data),
// com filtros de contagem (Tudo, Etapas e negócio, Retornos, Reuniões). O
// texto de cada evento é o mesmo da gaveta antiga (useCardHistorico): ícone,
// cor, título, quem fez, quando e o detalhe; nunca erro bruto (HS-04).
const props = defineProps({
  dias: { type: Array, required: true },
  carregando: { type: Boolean, default: false },
  // #1498 — funil de Atender: "Etapas e assunto".
  venda: { type: Boolean, default: true },
});

const { t } = useI18n();
const H = 'CRM_CARD.HISTORICO';
const GRUPOS = ['tudo', 'negocio', 'retornos', 'reunioes'];
const grupoDe = tipo => {
  const texto = String(tipo || '');
  if (texto.startsWith('meeting_') || texto.startsWith('booking_'))
    return 'reunioes';
  if (
    texto.startsWith('follow_up_') ||
    texto.startsWith('ai_followup_') ||
    texto === 'automation_follow_up_created'
  )
    return 'retornos';
  return 'negocio';
};
const filtro = ref('tudo');
const abas = ref([]);
const contagem = computed(() =>
  props.dias
    .flatMap(dia => dia.itens)
    .reduce(
      (total, item) => {
        const grupo = grupoDe(item.tipo);
        return { ...total, tudo: total.tudo + 1, [grupo]: total[grupo] + 1 };
      },
      { tudo: 0, negocio: 0, retornos: 0, reunioes: 0 }
    )
);
const visiveis = computed(() =>
  props.dias
    .map(dia => ({
      ...dia,
      itens: dia.itens.filter(
        item => filtro.value === 'tudo' || grupoDe(item.tipo) === filtro.value
      ),
    }))
    .filter(dia => dia.itens.length)
);
const mover = evento => {
  const atual = GRUPOS.indexOf(filtro.value);
  const passos = { ArrowRight: 1, ArrowLeft: -1 };
  let proximo = atual;
  if (evento.key === 'Home') proximo = 0;
  else if (evento.key === 'End') proximo = GRUPOS.length - 1;
  else if (passos[evento.key]) {
    const rtl = evento.currentTarget.closest('[dir="rtl"]') ? -1 : 1;
    proximo =
      (atual + passos[evento.key] * rtl + GRUPOS.length) % GRUPOS.length;
  } else return;
  evento.preventDefault();
  filtro.value = GRUPOS[proximo];
  nextTick(() => abas.value[proximo]?.focus());
};
</script>

<template>
  <section class="flex flex-col gap-4" data-tela="historico">
    <div
      role="tablist"
      :aria-label="t(`${H}.FILTRO`)"
      class="flex flex-wrap gap-2"
    >
      <button
        v-for="(grupo, indice) in GRUPOS"
        :id="`historico-aba-${grupo}`"
        :key="grupo"
        :ref="el => (abas[indice] = el)"
        type="button"
        role="tab"
        :aria-selected="filtro === grupo"
        aria-controls="historico-lista"
        :tabindex="filtro === grupo ? 0 : -1"
        class="inline-flex min-h-11 items-center gap-2 rounded-xl px-3 ring-1 ring-inset text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          filtro === grupo
            ? 'ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
            : 'ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-slate-7'
        "
        @click="filtro = grupo"
        @keydown="mover"
      >
        {{
          t(
            grupo === 'negocio' && !venda
              ? `${H}.GRUPO.ASSUNTO`
              : `${H}.GRUPO.${grupo.toUpperCase()}`
          )
        }}
        <span class="rounded-md bg-n-alpha-2 px-1.5 text-xs text-n-slate-11">
          {{ contagem[grupo] }}
        </span>
      </button>
    </div>

    <div
      id="historico-lista"
      role="tabpanel"
      :aria-labelledby="`historico-aba-${filtro}`"
      tabindex="0"
      class="flex flex-col gap-5 outline-none"
    >
      <section
        v-for="dia in visiveis"
        :key="dia.dia"
        class="flex flex-col gap-2"
      >
        <h3 class="mb-0 text-sm font-semibold text-n-slate-11">
          {{ dia.rotulo }}
        </h3>
        <ol class="m-0 flex list-none flex-col gap-2 p-0">
          <li
            v-for="item in dia.itens"
            :key="item.id"
            :data-evento="item.tipo"
            class="flex items-start gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
          >
            <span
              class="grid size-9 shrink-0 place-items-center rounded-full"
              :class="item.toneClass"
              aria-hidden="true"
            >
              <span class="size-4" :class="item.icon" />
            </span>
            <span class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span
                class="flex flex-wrap items-baseline justify-between gap-x-3"
              >
                <span class="text-[0.9375rem] font-medium text-n-slate-12">{{
                  item.title
                }}</span>
                <span class="text-xs text-n-slate-11">{{
                  item.relativeTime
                }}</span>
              </span>
              <span class="text-sm text-n-slate-11">{{ item.actor }}</span>
              <span v-if="item.detail" class="text-sm text-n-slate-12">{{
                item.detail
              }}</span>
            </span>
          </li>
        </ol>
      </section>
      <p
        v-if="!visiveis.length && !carregando"
        class="mb-0 rounded-2xl border border-dashed border-n-weak px-4 py-10 text-center text-base text-n-slate-12"
      >
        {{ t(dias.length ? `${H}.VAZIO_FILTRO` : `${H}.VAZIO`) }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">{{ t(`${H}.ULTIMOS_25`) }}</p>
    </div>
  </section>
</template>
