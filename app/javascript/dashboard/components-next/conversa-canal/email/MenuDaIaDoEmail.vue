<script setup>
// #1872 — o menu do ✨ no editor de e-mail, com a IA do cliente (useIaDoEmail). Mexer no
// texto (melhorar, tom, corrigir) só com texto escrito; sugerir resposta e resumir só com
// conversa (na gaveta Escrever o e-mail ainda não tem conversa). Os tons ficam à vista, sem
// submenu de passar o mouse, para o teclado e o toque alcançarem.
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  useId,
  useTemplateRef,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import NovaConversaMaisAbaixo from 'dashboard/components-next/NovaConversa/NovaConversaMaisAbaixo.vue';

const props = defineProps({
  temTexto: { type: Boolean, default: false },
  temConversa: { type: Boolean, default: false },
  // A raiz do editor deste menu (o slot do Editor a passa): para onde o foco volta e onde o Esc vale.
  editor: { type: null, default: null },
});

const emit = defineEmits(['executar', 'fechar']);
const { t } = useI18n();

const ITEM =
  'flex w-full min-h-11 items-center gap-2 rounded-lg px-3 text-start text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';

const tons = computed(() => [
  {
    acao: 'professional',
    rotulo: t('CONVERSA_CANAL.EMAIL.IA.TOM.PROFISSIONAL'),
  },
  { acao: 'casual', rotulo: t('CONVERSA_CANAL.EMAIL.IA.TOM.CASUAL') },
  { acao: 'straightforward', rotulo: t('CONVERSA_CANAL.EMAIL.IA.TOM.DIRETO') },
  { acao: 'confident', rotulo: t('CONVERSA_CANAL.EMAIL.IA.TOM.CONFIANTE') },
  { acao: 'friendly', rotulo: t('CONVERSA_CANAL.EMAIL.IA.TOM.AMIGAVEL') },
]);

const daConversa = computed(() =>
  props.temConversa
    ? [
        {
          acao: 'reply_suggestion',
          rotulo: t('CONVERSA_CANAL.EMAIL.IA.SUGERIR_RESPOSTA'),
          icone: 'i-fluent-chat-sparkle-16-regular',
        },
        {
          acao: 'summarize',
          rotulo: t('CONVERSA_CANAL.EMAIL.IA.RESUMIR'),
          icone: 'i-fluent-text-bullet-list-square-sparkle-32-regular',
        },
      ]
    : []
);

// Teclado: o foco entra no menu ao abrir (Tab percorre as ações); o Esc, com o foco no menu ou
// no editor dele, fecha e devolve o foco ao texto do editor.
const menu = useTemplateRef('menu');
const caixa = useTemplateRef('caixa');
const conteudo = useTemplateRef('conteudo');
const idDaLista = useId();
const MARGEM = 8;
const LARGURA = 256;

// O menu fica preso à tela (fixed), não à caixa de resposta: a caixa tem rolagem própria e cortava
// o menu, e abrir "para cima" dentro dela não tinha espaço. Cabe embaixo do ✨: abre embaixo. Não
// cabe e há mais espaço em cima: abre para cima. Senão, no lado maior, com altura máxima e
// rolagem própria, avisada pelo mesmo indicador da gaveta (NovaConversaMaisAbaixo).
const posicao = ref({});

const alturaInteira = () => {
  const borda = menu.value.offsetHeight - caixa.value.clientHeight;
  return caixa.value.scrollHeight + Math.max(borda, 0);
};

const lugarNaTela = (ancora, altura, largura) => {
  const abaixo = window.innerHeight - ancora.bottom - 2 * MARGEM;
  const acima = ancora.top - 2 * MARGEM;
  const left = Math.min(
    Math.max(ancora.left, MARGEM),
    window.innerWidth - largura - MARGEM
  );
  if (altura <= abaixo) return { top: ancora.bottom + MARGEM, left };
  if (acima > abaixo) {
    const alto = Math.min(altura, acima);
    return { top: ancora.top - MARGEM - alto, left, maxHeight: alto };
  }
  return { top: ancora.bottom + MARGEM, left, maxHeight: abaixo };
};

const emPixels = lugar =>
  Object.fromEntries(
    Object.entries(lugar).map(([chave, valor]) => [chave, `${valor}px`])
  );

const posicionar = async () => {
  const el = menu.value;
  const ancora = (
    props.editor?.querySelector('.ProseMirror-copilot') ?? props.editor
  )?.getBoundingClientRect();
  if (!el || !caixa.value || !ancora) return;
  const lugar = lugarNaTela(ancora, alturaInteira(), el.offsetWidth || LARGURA);
  posicao.value = emPixels(lugar);
  await nextTick();
  // Um ancestral com transform/filter muda a referência do fixed: corrige pela diferença medida.
  const real = el.getBoundingClientRect();
  if (!real.width) return;
  const dx = lugar.left - real.left;
  const dy = lugar.top - real.top;
  if (!dx && !dy) return;
  posicao.value = emPixels({
    ...lugar,
    left: lugar.left + dx,
    top: lugar.top + dy,
  });
};

// A página ou a caixa rolou, ou a janela mudou: o menu acompanha o ✨ (a rolagem do próprio menu, não).
const aoRolar = evento => {
  if (menu.value?.contains(evento.target)) return;
  posicionar();
};
useEventListener(window, 'scroll', aoRolar, { capture: true, passive: true });
useEventListener(window, 'resize', posicionar, { passive: true });

// O foco volta ao texto do editor (o ✨ do Chatwoot não recebe foco).
const focarTexto = () =>
  props.editor?.querySelector('[contenteditable="true"]')?.focus();

onMounted(() => {
  // Sem preventScroll o navegador rolava a caixa para mostrar o menu, e ele cobria o ✨.
  menu.value?.focus({ preventScroll: true });
  posicionar();
});

// Qualquer fechamento (Esc, clique fora, ação escolhida) com o foco no menu devolve o foco ao
// texto; sem isso, o menu sai da tela com o foco e ele cai no BODY.
onBeforeUnmount(() => {
  if (menu.value?.contains(document.activeElement)) focarTexto();
});

const fechar = () => {
  focarTexto();
  emit('fechar');
};

const aoTeclar = evento => {
  if (evento.key !== 'Escape') return;
  evento.preventDefault();
  evento.stopPropagation();
  fechar();
};

useEventListener(() => props.editor, 'keydown', aoTeclar, { capture: true });
// A seta "descer", alcançada pelo Tab, some no fim da lista e o foco cai no BODY: o Esc ainda
// fecha o menu.
useEventListener(document, 'keydown', evento => {
  if (document.activeElement === document.body) aoTeclar(evento);
});
</script>

<template>
  <div
    ref="menu"
    role="group"
    tabindex="-1"
    :aria-label="$t('CONVERSA_CANAL.EMAIL.IA.TITULO')"
    class="fixed z-50 flex w-64 flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-[0_8px_30px_rgba(0,0,0,0.15)] focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :style="posicao"
    data-menu-da-ia
    @keydown="aoTeclar"
  >
    <div
      :id="idDaLista"
      ref="caixa"
      class="min-h-0 flex-1 overflow-y-auto p-1.5"
      data-lista-da-ia
    >
      <div ref="conteudo" class="flex flex-col gap-0.5">
        <template v-if="temTexto">
          <button
            type="button"
            :class="ITEM"
            data-acao="improve"
            @click="emit('executar', 'improve')"
          >
            <span
              class="i-fluent-pen-sparkle-24-regular size-4 text-n-iris-10"
            />
            {{ $t('CONVERSA_CANAL.EMAIL.IA.MELHORAR') }}
          </button>
          <button
            type="button"
            :class="ITEM"
            data-acao="fix_spelling_grammar"
            @click="emit('executar', 'fix_spelling_grammar')"
          >
            <span
              class="i-fluent-flow-sparkle-24-regular size-4 text-n-iris-10"
            />
            {{ $t('CONVERSA_CANAL.EMAIL.IA.CORRIGIR') }}
          </button>
          <p class="px-3 pt-2 pb-1 text-xs font-medium text-n-slate-11">
            {{ $t('CONVERSA_CANAL.EMAIL.IA.MUDAR_TOM') }}
          </p>
          <div class="flex flex-wrap gap-1 px-2 pb-1">
            <button
              v-for="tom in tons"
              :key="tom.acao"
              type="button"
              class="min-h-11 rounded-full border border-n-weak px-3 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :data-acao="tom.acao"
              @click="emit('executar', tom.acao)"
            >
              {{ tom.rotulo }}
            </button>
          </div>
        </template>
        <p v-else class="px-3 py-2 text-sm text-n-slate-11" data-escreva-antes>
          {{ $t('CONVERSA_CANAL.EMAIL.IA.ESCREVA_ANTES') }}
        </p>

        <template v-if="daConversa.length">
          <div class="my-1 h-px bg-n-weak" />
          <button
            v-for="item in daConversa"
            :key="item.acao"
            type="button"
            :class="ITEM"
            :data-acao="item.acao"
            @click="emit('executar', item.acao)"
          >
            <span class="size-4 text-n-iris-10" :class="item.icone" />
            {{ item.rotulo }}
          </button>
        </template>
      </div>
    </div>
    <NovaConversaMaisAbaixo
      :caixa="caixa"
      :conteudo="conteudo"
      :controla="idDaLista"
    />
  </div>
</template>
