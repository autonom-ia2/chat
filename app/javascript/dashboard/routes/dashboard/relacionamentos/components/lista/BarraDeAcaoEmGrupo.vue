<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MenuMaisAcoes from './MenuMaisAcoes.vue';

// #2894 — a barra que aparece embaixo ao marcar alguém: "12 marcadas", a ação
// principal (Mandar mensagem) e as outras. Em 390 px só o principal fica à
// vista; Criar cards e Etiqueta vão para o menu "⋯" junto com Apagar.
defineProps({
  quantas: { type: Number, required: true },
});
const emit = defineEmits([
  'mandarMensagem',
  'criarCards',
  'etiqueta',
  'apagar',
  'fechar',
]);

const { t } = useI18n();

const aoEscolherNoMenu = id => {
  const comandos = {
    criarCards: () => emit('criarCards'),
    etiqueta: () => emit('etiqueta'),
    apagar: () => emit('apagar'),
  };
  comandos[id]?.();
};

const itensDoMenu = computed(() => [
  {
    id: 'criarCards',
    rotulo: t('RELACIONAMENTOS.LISTA.BARRA.CRIAR_CARDS'),
    icone: 'i-lucide-kanban',
    soNoCelular: true,
  },
  {
    id: 'etiqueta',
    rotulo: t('RELACIONAMENTOS.LISTA.BARRA.ETIQUETA'),
    icone: 'i-lucide-tag',
    soNoCelular: true,
  },
  {
    id: 'apagar',
    rotulo: t('RELACIONAMENTOS.LISTA.BARRA.APAGAR'),
    icone: 'i-lucide-trash-2',
    destrutivo: true,
  },
]);
</script>

<template>
  <div
    data-relacionamentos="barra"
    role="region"
    :aria-label="t('RELACIONAMENTOS.LISTA.BARRA.ROTULO')"
    class="flex flex-wrap items-center gap-2 p-3 shadow-xl rounded-2xl bg-n-solid-1 ring-1 ring-n-weak sm:gap-3 sm:px-4"
  >
    <p
      aria-live="polite"
      class="order-1 flex-1 m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:order-1 sm:me-1 sm:flex-none"
    >
      {{
        t('RELACIONAMENTOS.LISTA.MARCADAS.QUANTAS', { count: quantas }, quantas)
      }}
    </p>
    <Button
      class="order-3 flex-1 min-h-11 min-w-0 whitespace-nowrap sm:order-2 sm:flex-none"
      icon="i-lucide-send"
      data-relacionamentos="mandar-mensagem"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.MANDAR_MENSAGEM')"
      @click="emit('mandarMensagem')"
    />
    <Button
      slate
      faded
      class="hidden min-h-11 sm:order-3 sm:inline-flex"
      icon="i-lucide-kanban"
      data-relacionamentos="criar-cards"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.CRIAR_CARDS')"
      @click="emit('criarCards')"
    />
    <Button
      slate
      faded
      class="hidden min-h-11 sm:order-4 sm:inline-flex"
      icon="i-lucide-tag"
      data-relacionamentos="etiqueta"
      :label="t('RELACIONAMENTOS.LISTA.BARRA.ETIQUETA')"
      @click="emit('etiqueta')"
    />
    <MenuMaisAcoes
      class="order-4 sm:order-5"
      :itens="itensDoMenu"
      @escolher="aoEscolherNoMenu"
    />
    <Button
      ghost
      slate
      class="order-2 size-11 sm:order-6 sm:ms-auto"
      icon="i-lucide-x"
      :aria-label="t('RELACIONAMENTOS.LISTA.MARCADAS.DESMARCAR')"
      @click="emit('fechar')"
    />
    <!-- Celular: quebra a linha entre "marcadas ×" e "Mandar mensagem ⋯". -->
    <span
      data-quebra-de-linha
      class="order-2 h-0 basis-full sm:hidden"
      aria-hidden="true"
    />
  </div>
</template>
