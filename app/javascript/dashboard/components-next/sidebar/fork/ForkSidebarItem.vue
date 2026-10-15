<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import Icon from 'next/icon/Icon.vue';
import { folhasDe } from '../forkSidebarMenu';
import ForkContador from './ForkContador.vue';
import ForkSidebarFolha from './ForkSidebarFolha.vue';
import ForkSidebarSubgrupo from './ForkSidebarSubgrupo.vue';

// Um item do menu novo (#1617), aberto: ícone, nome, contagem ou pendência e, quando tem filhos, a lista dele.
// Clicar num item com filhos abre a lista e já leva à primeira tela, como o menu de sempre.
const props = defineProps({
  item: { type: Object, required: true },
  ativa: { type: Object, default: null },
  aberto: { type: Boolean, default: false },
  tema: { type: Object, required: true },
  contagem: { type: Number, default: 0 },
  pendencia: { type: String, default: '' },
});

const emit = defineEmits(['alternar', 'navegou']);

const router = useRouter();

const temFilhos = computed(() => Boolean(props.item.children?.length));
const souAtivo = computed(
  () => !temFilhos.value && props.ativa?.folha?.name === props.item.name
);
const contemAtiva = computed(
  () => temFilhos.value && props.ativa?.item.name === props.item.name
);
// Só o item que contém a tela marca o filho: Etiquetas existem em Conversas e em Contatos com o mesmo nome.
const ativaNome = computed(() =>
  contemAtiva.value ? props.ativa.folha?.name || '' : ''
);
// Aberto ou fechado é escolha da pessoa (o Nav abre sozinho só quando ela navega para uma tela do grupo).
const mostraFilhos = computed(() => props.aberto);
const idDaLista = computed(
  () => `fork-item-${props.item.name.split(' ').join('-')}`
);

const alternar = () => {
  // Abrir um grupo que não tem a tela atual já leva à primeira tela dele, como o menu de sempre.
  if (!mostraFilhos.value && !contemAtiva.value) {
    const [primeira] = folhasDe(props.item);
    if (primeira) {
      router.push(primeira.to);
      emit('navegou');
    }
  }
  emit('alternar', props.item.name);
};

const ir = (navegar, evento) => {
  navegar(evento);
  emit('navegou');
};

const classesDaLinha = computed(() => {
  if (souAtivo.value) return props.tema.ativo;
  // Fechado com a tela atual dentro: o próprio item fica realçado, para a pessoa não se perder.
  if (contemAtiva.value && !mostraFilhos.value)
    return props.tema.paiFechadoAtivo;
  if (contemAtiva.value) return [props.tema.paiAtivo, props.tema.passar];
  return [props.tema.texto, props.tema.passar];
});
const classesDoIcone = computed(() => {
  if (souAtivo.value) return props.tema.iconeAtivo;
  // O pai aberto mantém o ícone visível (na barra de marca o 'ativo' é da cor do fundo).
  if (contemAtiva.value) return props.tema.iconePai;
  return props.tema.icone;
});
</script>

<template>
  <li class="grid min-w-0 gap-0.5">
    <RouterLink
      v-if="!temFilhos"
      v-slot="{ href, navigate }"
      :to="item.to"
      custom
    >
      <a
        :href="href"
        :data-menu-item="item.name"
        :aria-current="souAtivo ? 'page' : undefined"
        class="flex items-center min-w-0 gap-3 px-3 text-[0.9375rem] leading-5 transition-colors duration-150 min-h-11 rounded-xl motion-reduce:transition-none"
        :class="[tema.foco, classesDaLinha]"
        @click="ir(navigate, $event)"
      >
        <Icon
          v-if="item.icon"
          :icon="item.icon"
          class="size-5 shrink-0"
          :class="classesDoIcone"
          aria-hidden="true"
        />
        <span
          v-if="pendencia"
          class="flex flex-col items-start flex-1 min-w-0 gap-1 py-2"
        >
          <span class="max-w-full truncate">{{ item.label }}</span>
          <span
            data-pendencia
            class="rounded-full px-2 py-0.5 text-xs font-semibold leading-4"
            :class="tema.pendencia"
          >
            {{ pendencia }}
          </span>
        </span>
        <span v-else class="flex-1 min-w-0 truncate">{{ item.label }}</span>
        <ForkContador
          v-if="!pendencia"
          :numero="contagem"
          :classes="souAtivo ? tema.contadorAtivo : tema.contador"
        />
      </a>
    </RouterLink>
    <template v-else>
      <button
        type="button"
        :data-menu-item="item.name"
        class="flex items-center w-full min-w-0 gap-3 px-3 text-[0.9375rem] leading-5 transition-colors duration-150 min-h-11 rounded-xl text-start motion-reduce:transition-none"
        :class="[tema.foco, classesDaLinha]"
        :aria-expanded="mostraFilhos"
        :aria-controls="idDaLista"
        @click="alternar"
      >
        <Icon
          v-if="item.icon"
          :icon="item.icon"
          class="size-5 shrink-0"
          :class="classesDoIcone"
          aria-hidden="true"
        />
        <span class="flex-1 min-w-0 truncate">{{ item.label }}</span>
        <ForkContador :numero="contagem" :classes="tema.contador" />
        <span
          class="i-lucide-chevron-down size-4 shrink-0 opacity-70 transition-transform duration-150 motion-reduce:transition-none"
          :class="{ 'rotate-180': mostraFilhos }"
          aria-hidden="true"
        />
      </button>
      <ul
        v-show="mostraFilhos"
        :id="idDaLista"
        class="relative grid gap-0.5 m-0 p-0 list-none min-w-0"
      >
        <span
          aria-hidden="true"
          class="absolute top-1 bottom-1 w-px start-[1.375rem]"
          :class="tema.trilho"
        />
        <template v-for="filho in item.children" :key="filho.name">
          <ForkSidebarSubgrupo
            v-if="filho.children"
            :subgrupo="filho"
            :folhas="filho.children"
            :ativa-nome="ativaNome"
            :tema="tema"
            @navegou="emit('navegou')"
          />
          <ForkSidebarFolha
            v-else
            :folha="filho"
            :ativa="filho.name === ativaNome"
            :tema="tema"
            @navegou="emit('navegou')"
          />
        </template>
      </ul>
    </template>
  </li>
</template>
