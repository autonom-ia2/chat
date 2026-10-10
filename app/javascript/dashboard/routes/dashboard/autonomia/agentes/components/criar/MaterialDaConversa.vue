<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// #1181 PR2 (protótipo materialMsg) — um arquivo ou foto mandado na conversa da criação, com o
// estado em palavras: lendo, pronto, na fila (antes do rascunho existir), atenção (não deu para
// ler: mandar outro ou tirar) e grande demais (passa de 25 MB).
const props = defineProps({
  material: { type: Object, required: true },
  estado: { type: String, required: true },
});

const emit = defineEmits(['mandarOutro', 'tirar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR.MATERIAL';

// "Tabela de preços.pdf" vira "Tabela de preços" (extensão curta some, como no protótipo); endereço
// de site fica inteiro.
const nomeVisivel = computed(() => {
  const nome = props.material.nome || '';
  const ponto = nome.lastIndexOf('.');
  const extensao = nome.slice(ponto + 1);
  const site = nome.startsWith('www.') || nome.includes('/');
  if (site || ponto <= 0 || extensao.length > 4 || extensao.includes(' ')) {
    return nome;
  }
  return nome.slice(0, ponto);
});

const problema = computed(() => ['atencao', 'grande'].includes(props.estado));
const icone = computed(() => {
  if (problema.value) return 'i-lucide-triangle-alert text-n-amber-11';
  return props.material.tipo === 'foto'
    ? 'i-lucide-image text-n-slate-11'
    : 'i-lucide-file-text text-n-slate-11';
});
</script>

<template>
  <div
    data-material
    :data-estado="estado"
    role="group"
    :aria-label="nomeVisivel"
    class="flex flex-col self-end gap-1 px-3 py-2 text-sm rounded-2xl max-w-[85%] ring-1 ring-inset"
    :class="
      problema
        ? 'bg-n-amber-2 ring-n-amber-6'
        : 'bg-n-solid-1 ring-n-weak dark:ring-n-slate-6'
    "
  >
    <p class="flex flex-wrap items-center gap-1.5 m-0 text-n-slate-12">
      <span class="sr-only">{{ t(`${NS}.VOCE_MANDOU`) }}</span>
      <span :class="icone" class="size-4 shrink-0" aria-hidden="true" />
      <span class="font-medium break-all">{{ nomeVisivel }}</span>
      <span aria-hidden="true" class="rounded-full size-1 bg-n-slate-9" />
      <span
        v-if="estado === 'lendo' || estado === 'enviando'"
        class="inline-flex items-center gap-1 text-n-slate-11"
      >
        <Spinner :size="14" aria-hidden="true" />
        {{ t(`${NS}.LENDO`) }}
      </span>
      <span
        v-else-if="estado === 'pronto'"
        class="inline-flex items-center gap-1 text-n-teal-11"
      >
        <span class="i-lucide-check size-4" aria-hidden="true" />
        {{ t(`${NS}.PRONTO`) }}
      </span>
      <span v-else-if="estado === 'fila'" class="text-n-slate-11">
        {{ t(`${NS}.FILA`) }}
      </span>
      <span v-else-if="estado === 'atencao'" class="text-n-slate-12">
        {{ t(`${NS}.ATENCAO`) }}
      </span>
    </p>
    <template v-if="problema">
      <p class="m-0 text-n-slate-12">
        {{ estado === 'grande' ? t(`${NS}.GRANDE`) : t(`${NS}.ATENCAO_TEXTO`) }}
      </p>
      <p class="flex flex-wrap gap-3 m-0">
        <button
          v-if="estado === 'atencao'"
          data-mandar-outro
          type="button"
          class="font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('mandarOutro')"
        >
          {{ t(`${NS}.MANDAR_OUTRO`) }}
        </button>
        <button
          data-tirar
          type="button"
          :aria-label="t(`${NS}.TIRAR_ARIA`, { nome: nomeVisivel })"
          class="font-semibold underline min-h-11 text-n-ruby-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('tirar', material)"
        >
          {{ t(`${NS}.TIRAR`) }}
        </button>
      </p>
    </template>
  </div>
</template>
