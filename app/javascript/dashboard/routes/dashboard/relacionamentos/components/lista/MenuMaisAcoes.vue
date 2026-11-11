<script setup>
import { nextTick, ref, useId, useTemplateRef } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — o "⋯" da barra de ação em grupo: um menu de verdade (role="menu"),
// que abre para cima, fecha com Esc ou clique fora e anda com as setas. Os
// itens vêm de quem usa: { id, rotulo, icone, destrutivo?, soNoCelular?,
// atributos? } (`atributos` vai no botão do item: a marca do robô de print).
// `rotulo` troca o nome acessível do "⋯"; `paraBaixo` abre a lista para baixo.
const props = defineProps({
  itens: { type: Array, required: true },
  rotulo: { type: String, default: '' },
  paraBaixo: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const idDoMenu = useId();
const raiz = useTemplateRef('raiz');
const aberto = ref(false);

const botoes = () =>
  [...(raiz.value?.querySelectorAll('[role="menuitem"]') ?? [])].filter(
    botao => botao.checkVisibility?.() ?? true
  );

const focarGatilho = () =>
  raiz.value?.querySelector('[aria-haspopup="menu"]')?.focus();

const fechar = () => {
  aberto.value = false;
  focarGatilho();
};

const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  botoes()[0]?.focus();
};

// O foco volta ao "⋯" antes de avisar: o item some ao fechar o menu e o diálogo
// que a ação abre devolve o foco, ao fechar, a quem o tinha (um botão visível).
const escolher = item => {
  aberto.value = false;
  focarGatilho();
  emit('escolher', item.id);
};

// Tab para fora do menu fecha. Sem `relatedTarget` (clique em botão no Safari,
// janela perdendo o foco) não decide: o clique fora já fecha por `onClickOutside`.
const aoSairDoFoco = evento => {
  const destino = evento.relatedTarget;
  if (aberto.value && destino && !raiz.value?.contains(destino)) {
    aberto.value = false;
  }
};

const andar = passo => {
  const lista = botoes();
  const atual = lista.indexOf(document.activeElement);
  lista[(atual + passo + lista.length) % lista.length]?.focus();
};

const aoTeclar = evento => {
  const comandos = {
    Escape: fechar,
    ArrowDown: () => andar(1),
    ArrowUp: () => andar(-1),
  };
  const comando = comandos[evento.key];
  if (!comando || !aberto.value) return;
  evento.preventDefault();
  comando();
};

onClickOutside(raiz, () => {
  aberto.value = false;
});
</script>

<template>
  <div ref="raiz" class="relative" @keydown="aoTeclar" @focusout="aoSairDoFoco">
    <Button
      slate
      faded
      class="size-11"
      icon="i-lucide-ellipsis"
      data-relacionamentos="mais-acoes"
      aria-haspopup="menu"
      :aria-expanded="aberto ? 'true' : 'false'"
      :aria-controls="idDoMenu"
      :aria-label="rotulo || t('RELACIONAMENTOS.LISTA.BARRA.MAIS')"
      @click="alternar"
    />
    <div
      v-show="aberto"
      :id="idDoMenu"
      role="menu"
      class="absolute z-20 flex min-w-52 flex-col gap-1 rounded-xl bg-n-solid-1 p-2 shadow-xl ring-1 ring-n-weak ltr:right-0 rtl:left-0"
      :class="paraBaixo ? 'top-full mt-2' : 'bottom-full mb-2'"
    >
      <button
        v-for="item in props.itens"
        :key="item.id"
        type="button"
        role="menuitem"
        v-bind="item.atributos"
        :data-acao="item.id"
        class="flex items-center gap-3 px-3 text-sm font-medium text-start border-0 rounded-lg bg-transparent min-h-11 hover:bg-n-alpha-1 focus-visible:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="[
          item.destrutivo ? 'text-n-ruby-11' : 'text-n-slate-12',
          { 'sm:hidden': item.soNoCelular },
        ]"
        @click="escolher(item)"
      >
        <span :class="item.icone" class="size-5 shrink-0" aria-hidden="true" />
        {{ item.rotulo }}
      </button>
    </div>
  </div>
</template>
