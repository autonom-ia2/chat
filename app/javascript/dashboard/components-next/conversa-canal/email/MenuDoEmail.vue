<script setup>
// "⋮" no cabeçalho de cada e-mail (#1786), adaptado do Gmail. Em grupos:
// responder a partir deste e-mail (Responder a todos, Encaminhar; o Responder fica à
// vista, ao lado), o que fazer com ele (Traduzir, Copiar link, Imprimir, Mostrar
// original), a conversa (Marcar como não lida) e, por último e em vermelho, Excluir.
// O menu só avisa a escolha; quem faz é o cartão.
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  podeTraduzir: { type: Boolean, default: false },
  podeExcluir: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher', 'acao']);
const { t } = useI18n();

const grupos = computed(() =>
  [
    [
      {
        resposta: 'todos',
        chave: 'RESPONDER_TODOS',
        icone: 'i-lucide-reply-all',
      },
      {
        resposta: 'encaminhar',
        chave: 'ENCAMINHAR',
        icone: 'i-lucide-forward',
      },
    ],
    [
      props.podeTraduzir && {
        acao: 'traduzir',
        chave: 'TRADUZIR',
        icone: 'i-lucide-languages',
      },
      { acao: 'copiar-link', chave: 'COPIAR_LINK', icone: 'i-lucide-link' },
      { acao: 'imprimir', chave: 'IMPRIMIR', icone: 'i-lucide-printer' },
      {
        acao: 'original',
        chave: 'MOSTRAR_ORIGINAL',
        icone: 'i-lucide-file-code-2',
      },
    ].filter(Boolean),
    [{ acao: 'nao-lida', chave: 'MARCAR_NAO_LIDA', icone: 'i-lucide-mail' }],
    props.podeExcluir
      ? [
          {
            acao: 'excluir',
            chave: 'EXCLUIR',
            icone: 'i-lucide-trash-2',
            perigo: true,
          },
        ]
      : [],
  ].filter(grupo => grupo.length)
);

const aberto = ref(false);
const lista = useTemplateRef('lista');
const botao = useTemplateRef('botao');
const itensDoMenu = () => [
  ...(lista.value?.querySelectorAll('[role=menuitem]') || []),
];

const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  itensDoMenu()[0]?.focus();
};
const fechar = () => {
  aberto.value = false;
  botao.value?.focus();
};
const escolher = item => {
  aberto.value = false;
  if (item.resposta) emit('escolher', item.resposta);
  else emit('acao', item.acao);
};

// Setas, Home e End andam pelos itens (padrão de menu do WAI-ARIA).
const mover = evento => {
  const itens = itensDoMenu();
  const atual = itens.indexOf(document.activeElement);
  const destinos = {
    ArrowDown: (atual + 1) % itens.length,
    ArrowUp: (atual - 1 + itens.length) % itens.length,
    Home: 0,
    End: itens.length - 1,
  };
  if (!(evento.key in destinos)) return;
  evento.preventDefault();
  itens[destinos[evento.key]]?.focus();
};
</script>

<template>
  <div class="relative">
    <button
      ref="botao"
      type="button"
      class="grid place-content-center size-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="t('CONVERSA_CANAL.EMAIL.MAIS_OPCOES')"
      :title="t('CONVERSA_CANAL.EMAIL.MAIS_OPCOES')"
      :aria-expanded="aberto"
      aria-haspopup="menu"
      data-menu-do-email
      @click="alternar"
    >
      <Icon icon="i-lucide-ellipsis-vertical" class="size-4" />
    </button>
    <div
      v-if="aberto"
      ref="lista"
      v-on-click-outside="[() => (aberto = false), { ignore: [botao] }]"
      role="menu"
      :aria-label="t('CONVERSA_CANAL.EMAIL.MAIS_OPCOES')"
      class="absolute end-0 top-full mt-1 z-30 w-72 py-1 rounded-xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
      @keydown.esc.prevent.stop="fechar"
      @keydown="mover"
    >
      <template v-for="(grupo, indice) in grupos" :key="indice">
        <div v-if="indice > 0" role="separator" class="my-1 h-px bg-n-weak" />
        <button
          v-for="item in grupo"
          :key="item.chave"
          type="button"
          role="menuitem"
          class="flex items-center gap-3 w-full min-h-11 px-3 text-sm text-start outline-none"
          :class="
            item.perigo
              ? 'text-n-ruby-11 hover:bg-n-ruby-3 focus-visible:bg-n-ruby-3'
              : 'text-n-slate-12 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1'
          "
          :data-item-do-menu="item.resposta || item.acao"
          @click="escolher(item)"
        >
          <Icon
            :icon="item.icone"
            class="size-4"
            :class="item.perigo ? 'text-n-ruby-11' : 'text-n-slate-11'"
          />
          {{ t(`CONVERSA_CANAL.EMAIL.${item.chave}`) }}
        </button>
      </template>
    </div>
  </div>
</template>
