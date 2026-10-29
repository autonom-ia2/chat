<script setup>
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';

// "··· Mais" do cartão de função (#2308): Duplicar e Apagar (numa função travada, só Duplicar). Menu do WAI-ARIA: os itens ficam fora do Tab (setas,
// Home e End andam por eles); Esc fecha e devolve o foco ao botão; Tab fecha e deixa o foco seguir a partir do botão;
// o menu fecha quando o foco sai dele (clique fora ou outro elemento).
const props = defineProps({
  nome: { type: String, required: true },
  podeApagar: { type: Boolean, default: true },
});

const emit = defineEmits(['duplicar', 'apagar']);

const aberto = ref(false);
const lista = useTemplateRef('lista');
const botao = useTemplateRef('botao');

const itens = computed(() =>
  [
    {
      acao: 'duplicar',
      chave: 'DUPLICAR',
      icone: 'i-lucide-copy',
      escolher: () => emit('duplicar'),
    },
    props.podeApagar && {
      acao: 'apagar',
      chave: 'APAGAR',
      icone: 'i-lucide-trash-2',
      perigo: true,
      escolher: () => emit('apagar'),
    },
  ].filter(Boolean)
);

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
  botao.value?.$el.focus();
};

// O foco volta ao "Mais" antes da ação: o diálogo que ela abre devolve o foco a ele ao fechar.
const escolher = item => {
  aberto.value = false;
  botao.value?.$el.focus();
  item.escolher();
};

// Tab: o foco volta ao botão antes de o navegador mover, então segue para o próximo elemento depois dele.
const sairPeloTab = () => {
  aberto.value = false;
  botao.value?.$el.focus();
};

// Só fecha quando o foco vai para outro elemento; sem destino (clique que não foca, como no Safari), quem fecha é o
// clique fora.
const aoSairDoFoco = ({ currentTarget, relatedTarget }) => {
  if (relatedTarget && !currentTarget.contains(relatedTarget))
    aberto.value = false;
};

const mover = evento => {
  if (evento.key === 'Tab') {
    sairPeloTab();
    return;
  }
  const elementos = itensDoMenu();
  const atual = elementos.indexOf(document.activeElement);
  const destinos = {
    ArrowDown: (atual + 1) % elementos.length,
    ArrowUp: (atual - 1 + elementos.length) % elementos.length,
    Home: 0,
    End: elementos.length - 1,
  };
  if (!(evento.key in destinos)) return;
  evento.preventDefault();
  elementos[destinos[evento.key]].focus();
};
</script>

<template>
  <div
    v-on-click-outside="() => (aberto = false)"
    class="relative"
    @keydown.esc="fechar"
    @focusout="aoSairDoFoco"
  >
    <Button
      ref="botao"
      data-mais
      :label="$t('FUNCOES_EQUIPE.CARTAO.MAIS')"
      :aria-label="$t('FUNCOES_EQUIPE.CARTAO.MAIS_ROTULO', { nome })"
      aria-haspopup="menu"
      :aria-expanded="aberto"
      icon="i-lucide-ellipsis"
      slate
      faded
      class="w-full min-h-11"
      @click="alternar"
    />
    <div
      v-if="aberto"
      ref="lista"
      role="menu"
      :aria-label="$t('FUNCOES_EQUIPE.CARTAO.MAIS_ROTULO', { nome })"
      class="absolute z-30 p-1 mt-2 border shadow-lg end-0 top-full min-w-44 rounded-xl border-n-weak bg-n-solid-1"
      @keydown="mover"
    >
      <button
        v-for="item in itens"
        :key="item.acao"
        type="button"
        role="menuitem"
        tabindex="-1"
        :data-acao="item.acao"
        class="flex items-center w-full gap-3 px-3 text-sm rounded-lg min-h-11 text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="item.perigo ? 'text-n-ruby-11' : 'text-n-slate-12'"
        @click="escolher(item)"
      >
        <span class="size-4 shrink-0" :class="item.icone" aria-hidden="true" />
        {{ $t(`FUNCOES_EQUIPE.CARTAO.${item.chave}`) }}
      </button>
    </div>
  </div>
</template>
