<script setup>
// Calendário Ouro — uma linha do dia: marcar como feito à esquerda, a hora,
// o que é e de quem, e UMA ação à direita (abrir conversa, ligar, entrar…).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { TIPOS, acaoDoItem } from './itensDoCalendario';
import { diasEntre, formatarHora } from './tempoNaConta';

const props = defineProps({
  item: { type: Object, required: true },
  hoje: { type: String, required: true },
  fuso: { type: String, required: true },
  idioma: { type: String, required: true },
  // Nome de quem recebe, quando não é você.
  para: { type: String, default: '' },
  concluindo: { type: Boolean, default: false },
});

const emit = defineEmits(['concluir', 'abrir', 'acao']);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.ITEM';

const tipo = computed(() => TIPOS[props.item.tipo]);
const acao = computed(() => acaoDoItem(props.item, { hoje: props.hoje }));
const hora = data => formatarHora(data, props.fuso, props.idioma);

const quando = computed(() => {
  const { item } = props;
  if (item.diaTodo) return { linha1: t(`${N}.DIA_TODO`), linha2: '' };
  const linha1 = hora(item.inicio);
  if (!item.atrasado || item.chave === props.hoje) {
    return { linha1, linha2: item.fim ? hora(item.fim) : '' };
  }
  const dias = diasEntre(item.chave, props.hoje);
  return {
    linha1: dias === 1 ? t(`${N}.ONTEM`) : t(`${N}.HA_DIAS`, { n: dias }, dias),
    linha2: linha1,
  };
});

const detalhe = computed(() =>
  [
    props.item.contato?.nome,
    props.para ? t(`${N}.PARA`, { nome: props.para }) : '',
  ].filter(Boolean)
);
</script>

<template>
  <li
    :data-item="item.id"
    :data-tipo="item.tipo"
    class="group flex min-h-[4.5rem] items-center gap-3 rounded-2xl border bg-n-solid-1 py-2 pe-3 ps-2 shadow-sm transition hover:border-n-slate-7"
    :class="[
      item.atrasado && item.chave !== hoje
        ? 'border-n-ruby-6'
        : 'border-n-weak',
      concluindo ? 'opacity-60' : '',
    ]"
  >
    <button
      v-if="item.podeConcluir"
      type="button"
      data-concluir
      :aria-label="t(`${N}.CONCLUIR`, { titulo: item.titulo })"
      :title="t(`${N}.CONCLUIR_CURTO`)"
      :disabled="concluindo"
      class="grid size-11 shrink-0 place-items-center rounded-full text-n-slate-9 transition hover:text-n-teal-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('concluir', item)"
    >
      <span
        class="grid size-6 place-items-center rounded-full border-2 border-current transition group-hover:border-n-teal-9"
      >
        <span
          class="i-lucide-check size-3.5 opacity-0 transition group-hover:opacity-100"
          :class="concluindo ? 'opacity-100' : ''"
          aria-hidden="true"
        />
      </span>
    </button>
    <span
      v-else
      class="grid size-11 shrink-0 place-items-center"
      aria-hidden="true"
    >
      <span
        class="grid size-8 place-items-center rounded-full"
        :class="tipo.tom"
      >
        <span class="size-4" :class="tipo.icone" />
      </span>
    </span>

    <div class="hidden w-16 shrink-0 flex-col leading-tight sm:flex">
      <span
        class="text-sm font-semibold tabular-nums"
        :class="
          item.atrasado && item.chave !== hoje
            ? 'text-n-ruby-11'
            : 'text-n-slate-12'
        "
      >
        {{ quando.linha1 }}
      </span>
      <span v-if="quando.linha2" class="text-xs tabular-nums text-n-slate-10">
        {{ quando.linha2 }}
      </span>
    </div>

    <button
      type="button"
      data-abrir
      class="flex min-h-11 min-w-0 flex-1 flex-col items-start justify-center rounded-xl px-1 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('abrir', item)"
    >
      <span
        class="text-sm font-semibold tabular-nums sm:hidden"
        :class="
          item.atrasado && item.chave !== hoje
            ? 'text-n-ruby-11'
            : 'text-n-slate-11'
        "
      >
        {{ [quando.linha1, quando.linha2].filter(Boolean).join(' · ') }}
      </span>
      <span
        class="line-clamp-2 w-full text-base font-medium text-n-slate-12 group-hover:text-n-blue-11 sm:line-clamp-1"
      >
        {{ item.titulo }}
      </span>
      <span
        class="flex w-full min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5 text-sm text-n-slate-11"
      >
        <span
          class="inline-flex items-center gap-1"
          :class="tipo.tom.split(' ')[1]"
        >
          <span class="size-3.5" :class="tipo.icone" aria-hidden="true" />
          {{ t(`CRM_CALENDARIO.TIPO.${item.tipo.toUpperCase()}`) }}
        </span>
        <span
          v-for="parte in detalhe"
          :key="parte"
          class="inline-flex min-w-0 items-center gap-2"
        >
          <span
            class="size-1 shrink-0 rounded-full bg-n-slate-8"
            aria-hidden="true"
          />
          <span class="truncate">{{ parte }}</span>
        </span>
        <span v-if="item.repete" class="inline-flex items-center gap-1">
          <span class="i-lucide-repeat size-3.5" aria-hidden="true" />
          {{ t(item.pausado ? `${N}.PAUSADO` : `${N}.REPETE`) }}
        </span>
      </span>
    </button>

    <component
      :is="acao.link ? 'a' : 'button'"
      v-if="acao"
      data-acao
      :type="acao.link ? undefined : 'button'"
      :href="acao.link"
      :target="
        acao.link && !acao.link.startsWith('tel:') ? '_blank' : undefined
      "
      :rel="acao.link ? 'noopener noreferrer' : undefined"
      :aria-label="t(`${N}.ACAO.${acao.chave}`)"
      class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center gap-2 rounded-xl px-3 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand sm:px-4"
      :class="
        acao.chave === 'ENTRAR'
          ? 'bg-n-iris-9 text-white hover:bg-n-iris-10'
          : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3'
      "
      @click="acao.link ? undefined : emit('acao', { item, acao })"
    >
      <span class="size-4" :class="acao.icone" aria-hidden="true" />
      <span class="hidden sm:inline">{{ t(`${N}.ACAO.${acao.chave}`) }}</span>
    </component>
  </li>
</template>
