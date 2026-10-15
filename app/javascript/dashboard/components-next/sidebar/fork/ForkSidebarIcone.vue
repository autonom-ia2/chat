<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { usePopoverState } from '../provider';
import SidebarCollapsedPopover from '../SidebarCollapsedPopover.vue';
import { folhasDe } from '../forkSidebarMenu';

// Menu novo recolhido (#1617): só o ícone. Item com filhos abre o mesmo balão do menu de sempre ao passar o
// mouse ou focar pelo teclado; o clique leva à primeira tela dele.
const props = defineProps({
  item: { type: Object, required: true },
  ativa: { type: Object, default: null },
  tema: { type: Object, required: true },
  contagem: { type: Number, default: 0 },
  pendencia: { type: String, default: '' },
});

const {
  activePopover,
  setActivePopover,
  closeActivePopover,
  scheduleClose,
  cancelClose,
} = usePopoverState();

const { t } = useI18n();

// O ponto do ícone é só visual: a contagem ou a pendência vão no nome do link para o leitor de tela.
const nomeAcessivel = computed(() => {
  let extra = props.pendencia;
  if (!extra && props.contagem > 0) {
    extra = t('FORK_SIDEBAR.NOVAS', { count: props.contagem }, props.contagem);
  }
  return extra
    ? t('FORK_SIDEBAR.ROTULO_COM_EXTRA', { item: props.item.label, extra })
    : props.item.label;
});

const temFilhos = computed(() => Boolean(props.item.children?.length));
const destino = computed(() => props.item.to || folhasDe(props.item)[0]?.to);
const marcado = computed(() => props.ativa?.item.name === props.item.name);
const balaoAberto = computed(
  () => temFilhos.value && activePopover.value === props.item.name
);

const gatilho = ref(null);
const retangulo = ref({ top: 0, left: 0, bottom: 0, right: 0 });
const ordenando = ref(false);

const abrir = () => {
  if (!temFilhos.value) return;
  cancelClose();
  // O RouterLink devolve o componente; a medida é do <a> dele.
  const caixa = gatilho.value?.$el?.getBoundingClientRect();
  if (caixa) {
    retangulo.value = {
      top: caixa.top,
      left: caixa.left,
      bottom: caixa.bottom,
      right: caixa.right,
    };
  }
  setActivePopover(props.item.name);
};

const sair = () => {
  if (!temFilhos.value || ordenando.value) return;
  scheduleClose(200);
};

const fechar = () => {
  if (activePopover.value === props.item.name) closeActivePopover();
};

const aoOrdenar = aberto => {
  ordenando.value = aberto;
  cancelClose();
};
</script>

<template>
  <li class="relative" @mouseenter="abrir" @mouseleave="sair">
    <RouterLink
      ref="gatilho"
      :to="destino"
      :data-menu-item="item.name"
      :aria-label="nomeAcessivel"
      :title="nomeAcessivel"
      :aria-current="marcado ? 'page' : undefined"
      class="relative grid transition-colors duration-150 size-11 place-items-center rounded-xl"
      :class="[tema.foco, marcado ? tema.ativo : [tema.icone, tema.passar]]"
      @focus="abrir"
    >
      <Icon :icon="item.icon" class="size-5" aria-hidden="true" />
      <span
        v-if="pendencia || contagem > 0"
        aria-hidden="true"
        class="absolute rounded-full top-2 end-2 size-2.5 ring-2"
        :class="
          pendencia
            ? 'bg-n-amber-9 ring-n-background'
            : 'bg-n-blue-9 ring-n-background'
        "
      />
    </RouterLink>
    <SidebarCollapsedPopover
      v-if="balaoAberto"
      :label="item.label"
      :children="item.children"
      :active-child="marcado ? ativa.folha : undefined"
      :trigger-rect="retangulo"
      @close="fechar"
      @mouseenter="cancelClose"
      @mouseleave="sair"
      @sort-toggle="aoOrdenar"
    />
  </li>
</template>
