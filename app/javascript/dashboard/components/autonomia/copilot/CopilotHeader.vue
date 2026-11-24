<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #3191 — cabeçalho do Copiloto da equipe, no desenho do Guia (#3184): a foto
// do agente num quadrado (contato é bolinha com iniciais), o nome dele e "Só
// você vê". Ao lado da conversa com o cliente, isso separa o que a pessoa fala
// com o cliente do que ela pergunta ao agente.
//
// Com mais de um copiloto na conta, o nome vira o botão de trocar: abre uma
// lista própria, com foto e nome, itens de 44 px e teclado do WAI-ARIA (o
// menu da casa tem itens de 32 px). "Novo assunto" vem escrito, e não "Nova
// conversa", que é o botão de falar com cliente.
// No celular o painel ocupa a tela: sai pela seta de voltar, à esquerda.
const props = defineProps({
  agente: {
    type: Object,
    default: null,
  },
  agentes: {
    type: Array,
    default: () => [],
  },
  // Só há o que recomeçar quando a conversa com o agente já começou.
  canReset: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['reset', 'close', 'trocar']);

const { t } = useI18n();

const menuAberto = ref(false);
const itens = ref([]);
const gatilho = ref(null);

const nome = computed(() => props.agente?.name || t('AUTONOMIA_COPILOT.TITLE'));
const foto = computed(() => props.agente?.avatar_url || '');
const podeTrocar = computed(() => props.agentes.length > 1);

const fecharMenu = () => {
  menuAberto.value = false;
};

const devolverFoco = async () => {
  await nextTick();
  gatilho.value?.focus();
};

const fecharEDevolverFoco = () => {
  if (!menuAberto.value) return;
  fecharMenu();
  devolverFoco();
};

// Abre já no agente da vez, como uma lista de escolha.
const alternarMenu = async () => {
  menuAberto.value = !menuAberto.value;
  if (!menuAberto.value) return;
  await nextTick();
  const ativo = props.agentes.findIndex(a => a.id === props.agente?.id);
  itens.value[Math.max(ativo, 0)]?.focus();
};

const escolher = agente => {
  fecharMenu();
  if (agente.id !== props.agente?.id) emit('trocar', agente);
  devolverFoco();
};

// Setas andam pelos itens; Esc fecha e devolve o foco; Tab sai e fecha.
const mover = (evento, indice) => {
  const total = props.agentes.length;
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
    <Button
      :aria-label="$t('AUTONOMIA_COPILOT.BACK')"
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
    <img
      v-if="foto"
      :src="foto"
      alt=""
      class="size-10 shrink-0 rounded-xl object-cover max-md:hidden"
      data-foto
    />
    <span
      v-else
      class="grid place-content-center size-10 shrink-0 rounded-xl bg-n-blue-3 text-n-blue-11 max-md:hidden"
      aria-hidden="true"
    >
      <span class="i-lucide-sparkles size-5" />
    </span>
    <div
      v-on-clickaway="fecharMenu"
      class="relative flex-1 min-w-0"
      @keydown.esc="fecharEDevolverFoco"
    >
      <button
        v-if="podeTrocar"
        ref="gatilho"
        type="button"
        data-trocar-agente
        :aria-label="$t('AUTONOMIA_COPILOT.CHANGE_AGENT', { nome })"
        :aria-expanded="menuAberto ? 'true' : 'false'"
        aria-haspopup="menu"
        class="flex flex-col items-start w-full min-w-0 min-h-11 px-2 -mx-2 rounded-lg text-start hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
        :class="menuAberto ? 'bg-n-alpha-2' : ''"
        @click="alternarMenu"
      >
        <span class="flex items-center gap-1 max-w-full min-w-0">
          <span
            class="text-base font-semibold leading-6 truncate text-n-slate-12"
          >
            {{ nome }}
          </span>
          <span
            class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
        </span>
        <span
          class="text-[0.8125rem] leading-5 truncate text-n-slate-11 max-md:hidden"
        >
          {{ $t('AUTONOMIA_COPILOT.SUBTITLE') }}
        </span>
      </button>
      <div v-else class="flex flex-col min-w-0">
        <h2
          class="mb-0 text-base font-semibold leading-6 truncate text-n-slate-12"
        >
          {{ nome }}
        </h2>
        <p
          class="mb-0 text-[0.8125rem] leading-5 truncate text-n-slate-11 max-md:hidden"
        >
          {{ $t('AUTONOMIA_COPILOT.SUBTITLE') }}
        </p>
      </div>
      <ul
        v-if="menuAberto"
        role="menu"
        :aria-label="$t('AUTONOMIA_COPILOT.AGENTS_MENU')"
        class="absolute top-full ltr:left-0 rtl:right-0 z-10 mt-1 mb-0 w-72 max-w-[calc(100vw-1rem)] list-none rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-lg"
      >
        <li v-for="(item, indice) in agentes" :key="item.id" role="none">
          <button
            :ref="el => (itens[indice] = el)"
            type="button"
            role="menuitemradio"
            :aria-checked="item.id === agente?.id ? 'true' : 'false'"
            :data-agente="item.id"
            class="flex items-center gap-3 w-full min-h-11 px-3 rounded-lg text-start text-base text-n-slate-12 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
            @click="escolher(item)"
            @keydown="mover($event, indice)"
          >
            <img
              v-if="item.avatar_url"
              :src="item.avatar_url"
              alt=""
              class="size-7 shrink-0 rounded-lg object-cover"
            />
            <span
              v-else
              class="grid place-content-center size-7 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <span class="flex-1 min-w-0 truncate">{{ item.name }}</span>
            <span
              v-if="item.id === agente?.id"
              class="i-lucide-check size-5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
    </div>
    <Button
      v-if="canReset"
      data-novo-assunto
      :label="$t('AUTONOMIA_COPILOT.NEW_TOPIC')"
      icon="i-lucide-square-pen"
      slate
      outline
      class="min-h-11 shrink-0"
      @click="emit('reset')"
    />
    <Button
      :aria-label="$t('AUTONOMIA_COPILOT.CLOSE')"
      icon="i-lucide-x"
      ghost
      slate
      lg
      class="max-md:hidden shrink-0"
      @click="emit('close')"
    />
  </div>
</template>
