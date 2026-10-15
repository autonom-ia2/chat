<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { diaCurto, diaDaParede, frase, horaDe, paredeDe } from './recorrencia';
import { nomesDeQuemRecebe } from './quemRecebe';
import { quemRecebeDaApi, repetirDaApi } from './paraApi';

// #1460 — no card, os lembretes que repetem: como repetem, a próxima vez e
// quem recebe. Cada linha é a vez pendente da série (crm_follow_ups com
// series); "Ver" abre a visão da repetição (próximas, pausar, encerrar).
const props = defineProps({
  retornos: { type: Array, default: () => [] },
  contexto: { type: Object, required: true },
  formato: { type: Object, required: true },
});
defineEmits(['ver']);

const { t, locale } = useI18n();
const S = 'CRM_LEMBRETE.LISTA';
const idioma = computed(() => locale.value.replace('_', '-'));

const linhas = computed(() =>
  props.retornos.map(item => {
    const serie = item.series;
    const proxima = paredeDe(item.due_at, serie.timezone);
    return {
      serie: {
        id: serie.id,
        titulo: item.title,
        situacao: serie.status === 'paused' ? 'pausada' : 'ativa',
      },
      frase: frase({
        t,
        idioma: idioma.value,
        juntar: props.formato.juntar,
        inicio: paredeDe(serie.starts_at, serie.timezone),
        repetir: repetirDaApi(serie),
      }),
      proxima: t(`${S}.PROXIMA`, {
        dia: diaCurto(diaDaParede(proxima), idioma.value),
        hora: horaDe(proxima),
      }),
      quem: props.formato.juntar(
        nomesDeQuemRecebe({
          quem: quemRecebeDaApi(item),
          dono: props.contexto.dono.value?.name,
          eu: props.contexto.eu.value?.name,
          agentes: props.contexto.agentes.value,
          membros: props.contexto.membros.value,
        })
      ),
    };
  })
);
</script>

<template>
  <section v-if="linhas.length" class="flex flex-col gap-3" data-que-repetem>
    <h3 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t(`${S}.TITULO`) }}
    </h3>
    <ul class="m-0 flex list-none flex-col gap-3 p-0">
      <li
        v-for="linha in linhas"
        :key="linha.serie.id"
        :data-serie="linha.serie.id"
        class="flex items-start gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
      >
        <span
          class="grid size-10 shrink-0 place-items-center rounded-2xl"
          :class="
            linha.serie.situacao === 'pausada'
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-blue-3 text-n-blue-11'
          "
          aria-hidden="true"
        >
          <span
            class="size-5"
            :class="
              linha.serie.situacao === 'pausada'
                ? 'i-lucide-pause'
                : 'i-lucide-repeat'
            "
          />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <span
            class="w-fit rounded-lg px-2 py-0.5 text-sm font-medium"
            :class="
              linha.serie.situacao === 'pausada'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-blue-3 text-n-blue-11'
            "
          >
            {{
              linha.serie.situacao === 'pausada'
                ? t(`${S}.PAUSADA`)
                : linha.frase
            }}
          </span>
          <p class="mb-0 text-base font-semibold text-n-slate-12">
            {{ linha.serie.titulo }}
          </p>
          <p
            v-if="linha.proxima && linha.serie.situacao !== 'pausada'"
            class="mb-0 text-sm text-n-slate-11"
          >
            {{ linha.proxima }}
          </p>
          <p v-if="linha.quem" class="mb-0 text-sm text-n-slate-11">
            {{ t(`${S}.AVISA`, { nomes: linha.quem }) }}
          </p>
        </div>
        <button
          type="button"
          data-serie-ver
          class="inline-flex min-h-11 shrink-0 items-center gap-1 rounded-xl px-3 text-sm font-medium text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="$emit('ver', linha.serie.id)"
        >
          {{ t(`${S}.VER`) }}
          <span
            class="i-lucide-chevron-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
  </section>
</template>
