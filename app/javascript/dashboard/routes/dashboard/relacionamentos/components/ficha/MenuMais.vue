<script setup>
import { useI18n } from 'vue-i18n';
import {
  DropdownBody,
  DropdownContainer,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';

// #2894 — o "⋯" da ficha: Alterar informações, Juntar com outra pessoa, Bloquear
// e Apagar. É o menu suspenso da casa; os itens são botões, então Tab e Enter
// funcionam, e Esc fecha e devolve o foco ao "⋯". Emite `acao` com o nome da
// escolha: alterar, juntar, bloquear ou apagar.
const emit = defineEmits(['acao']);

const { t } = useI18n();

const ITENS = [
  { evento: 'alterar', chave: 'ALTERAR_INFORMACOES', icone: 'i-lucide-pencil' },
  { evento: 'juntar', chave: 'JUNTAR', icone: 'i-lucide-git-merge' },
  { evento: 'bloquear', chave: 'BLOQUEAR', icone: 'i-lucide-ban' },
  { evento: 'apagar', chave: 'APAGAR', icone: 'i-lucide-trash-2' },
];

const PASSO_DA_SETA = { ArrowDown: 1, ArrowUp: -1 };

// O botão que abre fica no primeiro filho do contêiner; Esc o fecha pelo clique
// no mesmo botão (o jeito do contêiner alternar) e devolve o foco a ele. As
// setas passam de item em item enquanto o menu está aberto.
const aoTeclar = evento => {
  const raiz = evento.currentTarget;
  const botao = raiz.querySelector('[data-relacionamentos]');
  if (botao?.getAttribute('aria-expanded') !== 'true') return;
  if (evento.key === 'Escape') {
    evento.stopPropagation();
    botao.click();
    botao.focus();
    return;
  }
  const passo = PASSO_DA_SETA[evento.key];
  if (!passo) return;
  evento.preventDefault();
  const itens = [...raiz.querySelectorAll('.n-dropdown-item button')];
  const atual = itens.indexOf(document.activeElement);
  const proximo = (atual + passo + itens.length) % itens.length;
  itens[atual === -1 && passo > 0 ? 0 : proximo]?.focus();
};
</script>

<template>
  <div class="relative" @keydown="aoTeclar">
    <DropdownContainer>
      <template #trigger="{ toggle, isOpen }">
        <button
          type="button"
          data-relacionamentos="mais-acoes"
          aria-haspopup="menu"
          :aria-expanded="isOpen ? 'true' : 'false'"
          :aria-label="t('RELACIONAMENTOS_FICHA.ACOES.MAIS')"
          class="inline-flex items-center justify-center rounded-xl size-11 text-n-slate-11 ring-1 ring-inset ring-n-weak bg-n-solid-1 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="toggle"
        >
          <span class="i-lucide-ellipsis size-5" aria-hidden="true" />
        </button>
      </template>
      <DropdownBody class="top-12 ltr:right-0 rtl:left-0 min-w-64 z-50">
        <DropdownItem
          v-for="item in ITENS"
          :key="item.evento"
          :icon="item.icone"
          :label="t(`RELACIONAMENTOS_FICHA.ACOES.${item.chave}`)"
          :click="() => emit('acao', item.evento)"
          class="min-h-11"
        />
      </DropdownBody>
    </DropdownContainer>
  </div>
</template>
