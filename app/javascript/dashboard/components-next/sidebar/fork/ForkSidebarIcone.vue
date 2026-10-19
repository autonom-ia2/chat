<script setup>
import { computed, onBeforeUnmount, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { usePopoverState } from '../provider';
import SidebarCollapsedPopover from '../SidebarCollapsedPopover.vue';
import { folhasDe } from '../forkSidebarMenu';
import ForkDica from './ForkDica.vue';
// #1809: pastas da caixa de e-mail (Escrever, Entrada, Spam, Lixeira) também no balão.
import { comPastasNoBalao } from 'dashboard/components-next/conversa-canal/email/pastasDoEmailNoMenu';
import { useCaixaDeEmailNova } from 'dashboard/components-next/conversa-canal/email/caixaDeEmailNova';
import EscreverDoEmail from 'dashboard/components-next/conversa-canal/email/EscreverDoEmail.vue';

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
const ehEmailNova = useCaixaDeEmailNova();
const filhosDoBalao = computed(
  () => comPastasNoBalao(props.item, ehEmailNova).children
);

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

const medir = () => {
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
};

// Item sem filhos: dica com o nome depois de ~300 ms (mouse ou foco); some ao sair, ao perder o foco e no Esc.
const ESPERA_DA_DICA = 300;
const idDaDica = `fork-dica-${useId()}`;
const dicaVisivel = ref(false);
let relogio = null;
const mostrarDica = () => {
  clearTimeout(relogio);
  relogio = setTimeout(() => {
    medir();
    dicaVisivel.value = true;
  }, ESPERA_DA_DICA);
};
const esconderDica = () => {
  clearTimeout(relogio);
  dicaVisivel.value = false;
};
onBeforeUnmount(() => clearTimeout(relogio));

const abrir = () => {
  if (!temFilhos.value) {
    mostrarDica();
    return;
  }
  cancelClose();
  medir();
  setActivePopover(props.item.name);
};

const sair = () => {
  if (!temFilhos.value) {
    esconderDica();
    return;
  }
  if (ordenando.value) return;
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
      :aria-describedby="temFilhos ? undefined : idDaDica"
      :aria-current="marcado ? 'page' : undefined"
      class="relative grid transition-colors duration-150 size-11 place-items-center rounded-xl motion-reduce:transition-none"
      :class="[tema.foco, marcado ? tema.ativo : [tema.icone, tema.passar]]"
      @focus="abrir"
      @blur="esconderDica"
      @keydown.esc="esconderDica"
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
    <ForkDica
      v-if="!temFilhos"
      :id="idDaDica"
      :texto="nomeAcessivel"
      :visivel="dicaVisivel"
      :retangulo="retangulo"
    />
    <SidebarCollapsedPopover
      v-if="balaoAberto"
      :label="item.label"
      :children="filhosDoBalao"
      :active-child="marcado ? ativa.folha || undefined : undefined"
      :trigger-rect="retangulo"
      @close="fechar"
      @mouseenter="cancelClose"
      @mouseleave="sair"
      @sort-toggle="aoOrdenar"
    />
    <!-- Uma gaveta só, no ícone de Conversas (onde ficam as caixas). -->
    <EscreverDoEmail v-if="item.name === 'Conversation'" />
  </li>
</template>
