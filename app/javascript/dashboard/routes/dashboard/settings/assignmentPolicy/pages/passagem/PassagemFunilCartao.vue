<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { fraseDaSituacao } from './passagem';

// #1385 — um funil na lista da passagem, no padrão do cartão-frase (PassagemCartao, FunilResumoCartao): ícone, nome
// pequeno, a frase do estado e, no canto, "Abrir". O cartão inteiro é o botão; "Abrir" só mostra o que ele faz.
const props = defineProps({
  funil: { type: Object, required: true },
  situacao: { type: Object, default: null },
});

defineEmits(['abrir']);

const { t } = useI18n();
const E = 'CRM_KANBAN.PASSAGEM.LISTA.ESTADO';

const frase = computed(() => {
  const { chave, jeito, n, total } = fraseDaSituacao(props.situacao);
  return t(`${E}.${chave}`, {
    jeito: jeito ? t(`${E}.${jeito}`) : '',
    n,
    total,
  });
});
const ligada = computed(() =>
  ['ligada', 'parte'].includes(props.situacao?.estado)
);
const icone = computed(() =>
  ligada.value ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-10'
);
</script>

<template>
  <button
    type="button"
    :data-funil-cartao="funil.id"
    :aria-label="
      t('CRM_KANBAN.PASSAGEM.LISTA.ABRIR_FUNIL', { funil: funil.name })
    "
    :aria-describedby="`funil-estado-${funil.id}`"
    class="flex w-full items-center gap-3 rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-4 text-start shadow-sm transition hover:border-n-slate-7 focus-visible:border-n-blue-8 focus-visible:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-8 sm:gap-4 sm:p-5"
    @click="$emit('abrir', funil)"
  >
    <span
      class="grid size-10 shrink-0 place-items-center rounded-2xl sm:size-12"
      :class="icone"
      aria-hidden="true"
    >
      <span class="i-lucide-user-round-check size-5 sm:size-6" />
    </span>
    <span class="flex min-w-0 flex-1 flex-col gap-0.5">
      <span class="truncate text-sm font-medium text-n-slate-11">
        {{ funil.name }}
      </span>
      <span
        :id="`funil-estado-${funil.id}`"
        class="text-base leading-snug"
        :class="ligada ? 'text-n-slate-12' : 'text-n-slate-11'"
      >
        {{ frase }}
      </span>
    </span>
    <span
      class="inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-xl bg-n-alpha-2 px-3 text-sm font-medium text-n-slate-12"
      aria-hidden="true"
    >
      <span>{{ t('CRM_KANBAN.PASSAGEM.LISTA.ABRIR') }}</span>
      <span class="i-lucide-chevron-right size-4 rtl:rotate-180" />
    </span>
  </button>
</template>
