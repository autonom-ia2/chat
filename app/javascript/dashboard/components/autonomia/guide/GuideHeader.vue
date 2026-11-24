<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Cabeçalho próprio do Guia (#3184). Tem a cara de um assistente, não a de um
// contato: ícone num quadrado (contato é bolinha com iniciais), o nome curto e
// "só você vê". Ao lado da conversa de WhatsApp com a cliente, isso separa o
// que ela fala com a cliente do que ela pergunta ao Guia.
//
// "Novo assunto" vem escrito: ícone sem nome é adivinhação para quem não é da
// área, e "Nova conversa" já é o botão de falar com cliente. No celular também
// (o quadrado do ícone é que sai, para caber). O menu "Mais" diz por extenso
// o que abre: conversas anteriores, mudanças que o Guia fez (onde fica o
// desfazer) e o que o Guia anotou. Menu próprio, e não o DropdownMenu da casa,
// porque os itens dele têm 32 px e aqui o dedo pede 44.
// No celular o Guia ocupa a tela: sai pela seta de voltar, à esquerda.
// Alvos de 44 px; cada botão tem nome para o leitor de tela.
const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  // Só há o que reiniciar quando a conversa já começou.
  canReset: {
    type: Boolean,
    default: false,
  },
  // #861 — o histórico (conversas anteriores e "Feito pelo Guia", #855) está
  // aberto no lugar da conversa.
  vendoHistorico: {
    type: Boolean,
    default: false,
  },
  // #933 — "O que eu sei" está aberto no lugar da conversa.
  vendoMemoria: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['reset', 'historico', 'feitos', 'memoria', 'close']);

const { t } = useI18n();

const menuAberto = ref(false);
const itens = ref([]);
const gatilho = ref(null);
const voltar = ref(null);

// Histórico ou memória abertos: o topo vira "voltar à conversa".
const numaLista = computed(() => props.vendoHistorico || props.vendoMemoria);

// O mesmo botão que abriu a lista fecha a lista.
const abrirHistorico = () => emit('historico');
const abrirMemoria = () => emit('memoria');
const voltarAConversa = () =>
  props.vendoMemoria ? abrirMemoria() : abrirHistorico();

const itensDoMenu = computed(() => [
  {
    id: 'historico',
    rotulo: t('AUTONOMIA_GUIDE.HISTORY.TITLE'),
    icone: 'i-lucide-messages-square',
  },
  {
    id: 'feitos',
    rotulo: t('AUTONOMIA_GUIDE.HEADER.CHANGES'),
    icone: 'i-lucide-history',
  },
  {
    id: 'memoria',
    rotulo: t('AUTONOMIA_GUIDE.MEMORY.TITLE'),
    icone: 'i-lucide-notebook-pen',
  },
]);

const fecharMenu = () => {
  menuAberto.value = false;
};

// O foco não pode cair no vazio quando o menu some: volta ao "Mais" ou, se o
// item abriu uma lista, ao "Voltar" dela.
const devolverFoco = async () => {
  await nextTick();
  const alvo = voltar.value ?? gatilho.value;
  alvo?.$el?.focus();
};

const fecharEDevolverFoco = () => {
  if (!menuAberto.value) return;
  fecharMenu();
  devolverFoco();
};

// #3195 — com o menu aberto, o Esc é dele: para aqui, senão chega ao ouvinte
// do painel (AutonomiaGuideContainer) e fecha o Guia inteiro. Com o menu
// fechado, segue: Esc fecha o Guia como sempre.
// A lista tem tabindex -1: um clique na borda dela deixa o foco no menu (e não
// no body), e o Esc continua passando por aqui.
const aoApertarEsc = evento => {
  if (!menuAberto.value) return;
  evento.stopPropagation();
  fecharEDevolverFoco();
};

const alternarMenu = async () => {
  menuAberto.value = !menuAberto.value;
  if (!menuAberto.value) return;
  await nextTick();
  itens.value[0]?.focus();
};

const abrirFeitos = () => emit('feitos');
const acoes = {
  historico: abrirHistorico,
  feitos: abrirFeitos,
  memoria: abrirMemoria,
};

const escolher = id => {
  fecharMenu();
  acoes[id]();
  devolverFoco();
};

// Setas andam pelos itens; Esc fecha e devolve o foco; Tab sai e fecha.
// Padrão de menu do WAI-ARIA.
const mover = (evento, indice) => {
  const total = itensDoMenu.value.length;
  const passos = { ArrowDown: 1, ArrowUp: -1 };
  if (evento.key === 'Tab') {
    fecharMenu();
    return;
  }
  if (!passos[evento.key]) return;
  evento.preventDefault();
  itens.value[(indice + passos[evento.key] + total) % total]?.focus();
};
</script>

<template>
  <div
    class="flex items-center gap-2 h-16 shrink-0 ltr:pl-2 rtl:pr-2 ltr:pr-2 rtl:pl-2 md:ltr:pl-4 md:rtl:pr-4 border-b border-n-weak bg-n-solid-1"
  >
    <template v-if="numaLista">
      <Button
        ref="voltar"
        data-voltar-a-conversa
        :label="$t('AUTONOMIA_GUIDE.DONE.BACK')"
        ghost
        slate
        class="min-h-11"
        @click="voltarAConversa"
      >
        <template #icon>
          <span class="i-lucide-arrow-left size-4 shrink-0 rtl:rotate-180" />
        </template>
      </Button>
      <h2
        class="flex-1 mb-0 min-w-0 text-base font-medium truncate text-n-slate-12"
      >
        {{ title }}
      </h2>
    </template>
    <template v-else>
      <Button
        :aria-label="$t('AUTONOMIA_GUIDE.HEADER.BACK')"
        ghost
        slate
        lg
        class="md:hidden"
        @click="emit('close')"
      >
        <template #icon>
          <span class="i-lucide-arrow-left size-5 shrink-0 rtl:rotate-180" />
        </template>
      </Button>
      <span
        class="grid place-content-center size-10 shrink-0 rounded-xl bg-n-blue-3 text-n-blue-11 max-md:hidden"
        aria-hidden="true"
      >
        <span class="i-lucide-sparkles size-5" />
      </span>
      <div class="flex flex-col flex-1 min-w-0">
        <h2
          class="mb-0 text-base font-semibold leading-6 truncate text-n-slate-12"
        >
          {{ title }}
        </h2>
        <p
          class="mb-0 text-[0.8125rem] leading-5 truncate text-n-slate-11 max-md:hidden"
        >
          {{ $t('AUTONOMIA_GUIDE.HEADER.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="canReset"
        data-novo-assunto
        :label="$t('AUTONOMIA_GUIDE.HEADER.NEW_TOPIC')"
        icon="i-lucide-square-pen"
        slate
        outline
        class="min-h-11 shrink-0"
        @click="emit('reset')"
      />
      <div
        v-on-clickaway="fecharMenu"
        class="relative shrink-0"
        @keydown.esc="aoApertarEsc"
      >
        <Button
          ref="gatilho"
          data-mais
          :aria-label="$t('AUTONOMIA_GUIDE.HEADER.MORE')"
          :aria-expanded="menuAberto ? 'true' : 'false'"
          aria-haspopup="menu"
          icon="i-lucide-ellipsis-vertical"
          ghost
          slate
          lg
          :class="menuAberto ? 'bg-n-alpha-2' : ''"
          @click="alternarMenu"
        />
        <ul
          v-if="menuAberto"
          role="menu"
          tabindex="-1"
          :aria-label="$t('AUTONOMIA_GUIDE.HEADER.MORE')"
          class="absolute top-full ltr:right-0 rtl:left-0 z-10 mt-1 mb-0 w-72 max-w-[calc(100vw-1rem)] list-none rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-lg"
        >
          <li v-for="(item, indice) in itensDoMenu" :key="item.id" role="none">
            <button
              :ref="el => (itens[indice] = el)"
              type="button"
              role="menuitem"
              :data-item-do-menu="item.id"
              class="flex items-center gap-3 w-full min-h-11 px-3 rounded-lg text-start text-base text-n-slate-12 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
              @click="escolher(item.id)"
              @keydown="mover($event, indice)"
            >
              <span
                :class="item.icone"
                class="size-5 shrink-0 text-n-slate-11"
              />
              {{ item.rotulo }}
            </button>
          </li>
        </ul>
      </div>
      <Button
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.CLOSE')"
        icon="i-lucide-x"
        ghost
        slate
        lg
        class="max-md:hidden shrink-0"
        @click="emit('close')"
      />
    </template>
  </div>
</template>
