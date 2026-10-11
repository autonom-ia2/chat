<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ESTADO_PAGINA } from '../../utils/agendaDaPagina';

// #1181 (item A) — a frase do estado real da página de agendamento, igual na linha "Marca reuniões"
// e na gaveta. Estado que pede ação (pausada, sem ninguém, agenda pausada, não existe mais) vem em
// âmbar com ícone: a cor nunca fala sozinha. Frase com ação ("reativar", "escolha") só para quem
// gerencia; quem só vê lê o efeito. Os estados resolvidos nas páginas de agendamento levam "Abrir
// páginas de agendamento" quando quem vê pode abrir.
const props = defineProps({
  estado: { type: String, required: true },
  nome: { type: String, required: true },
  pagina: { type: String, default: '' },
  linkPaginas: { type: String, default: '' },
  gerencia: { type: Boolean, default: false },
});

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.AGENDA_ESTADO';

const CHAVE = {
  [ESTADO_PAGINA.NENHUMA]: 'NENHUMA',
  [ESTADO_PAGINA.NAO_EXISTE]: 'NAO_EXISTE',
  [ESTADO_PAGINA.PAUSADA]: 'PAUSADA',
  [ESTADO_PAGINA.SEM_NINGUEM]: 'SEM_NINGUEM',
  [ESTADO_PAGINA.AGENDA_PAUSADA]: 'AGENDA_PAUSADA',
  [ESTADO_PAGINA.ATIVA]: 'ATIVA',
};
const COM_ACAO = [ESTADO_PAGINA.NAO_EXISTE, ESTADO_PAGINA.PAUSADA];
const COM_LINK = [
  ESTADO_PAGINA.PAUSADA,
  ESTADO_PAGINA.SEM_NINGUEM,
  ESTADO_PAGINA.AGENDA_PAUSADA,
];

const alerta = computed(
  () => ![ESTADO_PAGINA.NENHUMA, ESTADO_PAGINA.ATIVA].includes(props.estado)
);
const chave = computed(() => {
  const base = CHAVE[props.estado];
  const soVer = COM_ACAO.includes(props.estado) && !props.gerencia;
  return soVer ? `${base}_SO_VER` : base;
});
const texto = computed(() =>
  t(`${NS}.${chave.value}`, { nome: props.nome, pagina: props.pagina })
);
const mostrarLink = computed(
  () => COM_LINK.includes(props.estado) && Boolean(props.linkPaginas)
);
</script>

<template>
  <div :data-estado-agenda="estado" class="flex flex-col gap-1">
    <p
      class="flex items-start gap-2 m-0 text-sm"
      :class="alerta ? 'text-n-amber-11' : 'text-n-slate-12'"
    >
      <span
        v-if="alerta"
        class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0"
        aria-hidden="true"
      />
      <span>{{ texto }}</span>
    </p>
    <a
      v-if="mostrarLink"
      data-abrir-paginas
      :href="linkPaginas"
      target="_blank"
      rel="noopener noreferrer"
      class="relative inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
    >
      {{ t(`${NS}.ABRIR_PAGINAS`) }}
      <span class="i-lucide-external-link size-4" aria-hidden="true" />
      <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
    </a>
  </div>
</template>
