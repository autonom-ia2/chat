<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBrandedSidebar } from 'dashboard/composables/useBrandedSidebar';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useOnboardingTrail } from 'dashboard/composables/useOnboardingTrail';
import { focusableIn } from 'dashboard/components-next/CampaignJourney/useModalFocus';
import { useSidebarContext } from '../provider';
import { acharAtivo, organizeForkMenu } from '../forkSidebarMenu';
import { publicarMenu } from './menuPublicado';
import { temaDoMenu } from './tema';
import ForkSidebarItem from './ForkSidebarItem.vue';
import ForkSidebarIcone from './ForkSidebarIcone.vue';
import ForkSidebarRecolher from './ForkSidebarRecolher.vue';
import ForkSidebarSeta from './ForkSidebarSeta.vue';
import { TELA_MEDIA_DE, useLarguraDoMenu } from './useLarguraDoMenu';
import { ehTelaDeTrabalho, useRecolherSozinho } from './useRecolherSozinho';
import { usePainelDoContatoRecolhido } from './usePainelDoContatoRecolhido';
import { useSetasDeRolagem } from './useSetasDeRolagem';

// Menu lateral novo (#1617). Recebe a lista que o Sidebar.vue já monta e só reorganiza (forkSidebarMenu.js).
// Fica no lugar da <nav> de sempre quando a flag `menu_lateral_novo` está ligada na conta.
const props = defineProps({
  itens: { type: Array, required: true },
  // Celular com a gaveta aberta: o foco fica preso dentro dela e o Esc fecha.
  gavetaAberta: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar']);

const ID_DA_LISTA = 'fork-menu-lista';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { accountScopedRoute } = useAccount();
const { uiSettings, updateUISettings } = useUISettings();
const { isAllowed, resolvePath, isCollapsed, sidebarWidth } =
  useSidebarContext();
const { brandedColor } = useBrandedSidebar();
const tema = computed(() => temaDoMenu(Boolean(brandedColor.value)));

// Primeiros passos: a pílula diz quantos faltam, e o item sai do topo quando a trilha termina.
const trilha = useOnboardingTrail();
const temPrimeirosPassos = computed(() =>
  props.itens.some(item => item.name === 'FirstSteps')
);
const pendentes = computed(
  () => trilha.passos.value.filter(passo => passo.status === 'pendente').length
);
const trilhaConcluida = computed(
  () => trilha.total.value > 0 && pendentes.value === 0
);
watch(
  temPrimeirosPassos,
  valor => {
    if (valor) trilha.carregar();
  },
  { immediate: true }
);

const organizado = computed(() =>
  organizeForkMenu(props.itens, {
    t,
    accountScopedRoute,
    trilhaConcluida: trilhaConcluida.value,
  })
);

watch(() => props.itens, publicarMenu, { immediate: true });

// O que a pessoa pode abrir: a mesma checagem de rota do menu de sempre (permissão, flag, instalação).
const podeAbrir = item => Boolean(item.to) && isAllowed(item.to);
const filtrar = item => {
  if (!item.children) return podeAbrir(item) ? item : null;
  const children = item.children
    .map(filho => filtrar(filho))
    .filter(filho => filho && (!filho.children || filho.children.length));
  return children.length ? { ...item, children } : null;
};
const visiveis = lista => lista.map(filtrar).filter(Boolean);

const topo = computed(() => visiveis(organizado.value.topo));
const grupos = computed(() =>
  organizado.value.grupos
    .map(grupo => ({ ...grupo, itens: visiveis(grupo.itens) }))
    .filter(grupo => grupo.itens.length)
);
const rodape = computed(() => visiveis(organizado.value.rodape));

const todos = computed(() => [
  ...topo.value,
  ...grupos.value.flatMap(grupo => grupo.itens),
  ...rodape.value,
]);
const ativa = computed(() => acharAtivo(todos.value, route, resolvePath));

// Grupos começam fechados e só abrem no clique (#1661, pedido do Rodrigo): abrir sozinho empurrava os outros grupos
// para fora da tela. Um aberto por vez. O grupo fechado que contém a tela atual continua realçado.
const abertoNome = ref(null);
const alternar = nome => {
  abertoNome.value = abertoNome.value === nome ? null : nome;
};

const contagemDe = item => {
  const chave = item.getterKeys?.count;
  return chave ? Number(store.getters[chave]) || 0 : 0;
};
const pendenciaDe = item =>
  item.name === 'FirstSteps' && pendentes.value > 0
    ? t(
        'FORK_SIDEBAR.FALTAM_PASSOS',
        { count: pendentes.value },
        pendentes.value
      )
    : '';

// Largura: 256px aberto, botão e atalho para recolher, recolhido sozinho em tela média sem escolha.
// Nas telas de trabalho (#1781) o menu recolhe sozinho em 30 s; no celular vale a gaveta de sempre.
const { width: larguraDaJanela } = useWindowSize();
const telaDeTrabalho = computed(
  () => larguraDaJanela.value >= TELA_MEDIA_DE && ehTelaDeTrabalho(route.name)
);
const {
  alternar: alternarLargura,
  anuncio,
  recolherSemSalvar,
  aplicar,
} = useLarguraDoMenu({
  sidebarWidth,
  isCollapsed,
  uiSettings,
  updateUISettings,
  telaDeTrabalho,
});
const recolherSozinho = useRecolherSozinho({
  route,
  telaDeTrabalho,
  isCollapsed,
  recolher: recolherSemSalvar,
  restaurar: aplicar,
});
usePainelDoContatoRecolhido({ route, uiSettings, updateUISettings });

// Gaveta do celular: foco preso, Esc fecha, foco volta para quem abriu.
const raiz = ref(null);
let quemAbriu = null;
const gaveta = () => raiz.value?.closest('aside');
const aoTeclar = evento => {
  if (evento.key === 'Escape') {
    evento.preventDefault();
    emit('fechar');
    return;
  }
  if (evento.key !== 'Tab') return;
  const itens = focusableIn(gaveta());
  if (!itens.length) return;
  const primeiro = itens[0];
  const ultimo = itens[itens.length - 1];
  const fora = !gaveta()?.contains(document.activeElement);
  if (evento.shiftKey && (document.activeElement === primeiro || fora)) {
    evento.preventDefault();
    ultimo.focus();
  } else if (!evento.shiftKey && (document.activeElement === ultimo || fora)) {
    evento.preventDefault();
    primeiro.focus();
  }
};
watch(
  () => props.gavetaAberta,
  async aberta => {
    if (aberta) {
      quemAbriu = document.activeElement;
      document.addEventListener('keydown', aoTeclar);
      await nextTick();
      raiz.value?.querySelector('a[href], button')?.focus();
      return;
    }
    document.removeEventListener('keydown', aoTeclar);
    if (quemAbriu?.isConnected) quemAbriu.focus();
    quemAbriu = null;
  }
);
onBeforeUnmount(() => document.removeEventListener('keydown', aoTeclar));

// O menu não rola sozinho na troca de tela (#1781): só a pessoa rola. A borda avisa quando tem mais.
const lista = ref(null);
const conteudo = ref(null);
const setas = useSetasDeRolagem(lista, conteudo, () => route.path);

const navegou = () => {
  recolherSozinho.depoisDoClique();
  if (props.gavetaAberta) emit('fechar');
};
</script>

<template>
  <div
    ref="raiz"
    data-menu-novo
    class="flex flex-col flex-grow min-h-0 min-w-0"
    @mouseenter="recolherSozinho.entrar"
    @mouseleave="recolherSozinho.sair"
    @focusin="recolherSozinho.focoEntrou"
    @focusout="recolherSozinho.focoSaiu"
  >
    <div v-if="gavetaAberta" class="flex justify-end px-3 pb-1">
      <button
        type="button"
        data-fechar-gaveta
        class="inline-flex items-center gap-2 px-3 text-[0.9375rem] rounded-xl min-h-11"
        :class="[tema.foco, tema.texto, tema.passar]"
        @click="emit('fechar')"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
        {{ t('FORK_SIDEBAR.FECHAR_GAVETA') }}
      </button>
    </div>
    <div class="relative flex flex-col flex-grow min-h-0">
      <nav
        :id="ID_DA_LISTA"
        ref="lista"
        :aria-label="t('FORK_SIDEBAR.MENU')"
        class="flex-grow min-h-0 overflow-y-auto overflow-x-hidden [scrollbar-width:thin]"
        :class="isCollapsed ? 'px-1.5 pb-3' : 'ps-3 pe-1 pb-4'"
      >
        <div ref="conteudo">
          <ul
            v-if="topo.length"
            class="grid gap-0.5 m-0 p-0 mb-3 list-none"
            :class="{ 'justify-items-center': isCollapsed }"
          >
            <template v-for="item in topo" :key="item.name">
              <ForkSidebarIcone
                v-if="isCollapsed"
                :item="item"
                :ativa="ativa"
                :tema="tema"
                :pendencia="pendenciaDe(item)"
              />
              <ForkSidebarItem
                v-else
                :item="item"
                :ativa="ativa"
                :tema="tema"
                :aberto="abertoNome === item.name"
                :pendencia="pendenciaDe(item)"
                @alternar="alternar"
                @navegou="navegou"
              />
            </template>
          </ul>
          <section
            v-for="grupo in grupos"
            :key="grupo.id"
            :aria-labelledby="
              isCollapsed ? undefined : `fork-grupo-${grupo.id}`
            "
            :aria-label="isCollapsed ? grupo.label : undefined"
            class="grid gap-1 mt-4 first-of-type:mt-1"
          >
            <h2
              v-if="!isCollapsed"
              :id="`fork-grupo-${grupo.id}`"
              class="m-0 px-3 pb-1 text-sm font-semibold leading-5"
              :class="tema.tituloGrupo"
            >
              {{ grupo.label }}
            </h2>
            <hr
              v-else
              aria-hidden="true"
              class="w-6 mx-auto my-1 border-t"
              :class="tema.linha"
            />
            <ul
              class="grid gap-0.5 m-0 p-0 list-none"
              :class="{ 'justify-items-center': isCollapsed }"
            >
              <template v-for="item in grupo.itens" :key="item.name">
                <ForkSidebarIcone
                  v-if="isCollapsed"
                  :item="item"
                  :ativa="ativa"
                  :tema="tema"
                  :contagem="contagemDe(item)"
                />
                <ForkSidebarItem
                  v-else
                  :item="item"
                  :ativa="ativa"
                  :tema="tema"
                  :aberto="abertoNome === item.name"
                  :contagem="contagemDe(item)"
                  @alternar="alternar"
                  @navegou="navegou"
                />
              </template>
            </ul>
          </section>
        </div>
      </nav>
      <div
        v-if="setas.acima.value"
        data-esmaecido-cima
        aria-hidden="true"
        class="absolute inset-x-0 top-0 h-10 to-transparent opacity-80 pointer-events-none z-[1]"
        :class="tema.esmaecidoCima"
      />
      <div
        v-if="setas.abaixo.value"
        data-esmaecido-baixo
        aria-hidden="true"
        class="absolute inset-x-0 bottom-0 h-10 to-transparent opacity-80 pointer-events-none z-[1]"
        :class="tema.esmaecidoBaixo"
      />
      <ForkSidebarSeta
        lado="acima"
        :visivel="setas.acima.value"
        :contagem="setas.itensAcima.value"
        :respirando="setas.respirando.value.acima"
        :recolhido="isCollapsed"
        :controla="ID_DA_LISTA"
        :tema="tema"
        @rolar="setas.rolarParaCima"
      />
      <ForkSidebarSeta
        lado="abaixo"
        :visivel="setas.abaixo.value"
        :contagem="setas.itensAbaixo.value"
        :respirando="setas.respirando.value.abaixo"
        :recolhido="isCollapsed"
        :controla="ID_DA_LISTA"
        :tema="tema"
        @rolar="setas.rolarParaBaixo"
      />
    </div>
    <ul
      v-if="rodape.length"
      data-menu-rodape
      class="relative z-10 grid gap-0.5 m-0 list-none border-t py-2"
      :class="[
        tema.linha,
        isCollapsed ? 'px-1.5 justify-items-center' : 'px-3',
      ]"
    >
      <template v-for="item in rodape" :key="item.name">
        <ForkSidebarIcone
          v-if="isCollapsed"
          :item="item"
          :ativa="ativa"
          :tema="tema"
        />
        <ForkSidebarItem
          v-else
          :item="item"
          :ativa="ativa"
          :tema="tema"
          @navegou="navegou"
        />
      </template>
      <ForkSidebarRecolher
        :recolhido="isCollapsed"
        :controla="ID_DA_LISTA"
        :tema="tema"
        :progresso="recolherSozinho.progresso.value"
        :sem-animacao="recolherSozinho.reduzido.value"
        @alternar="alternarLargura"
      />
    </ul>
    <p class="sr-only" aria-live="polite">{{ anuncio ? t(anuncio) : '' }}</p>
  </div>
</template>
