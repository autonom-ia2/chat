<script setup>
import { computed, isVNode } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ForkContador from './ForkContador.vue';
import PastasDoEmailNoMenu from 'dashboard/components-next/conversa-canal/email/PastasDoEmailNoMenu.vue';

// Um link de dentro de um item aberto do menu novo (#1617): Todas as conversas, Kanban, uma caixa…
// O `component` do upstream (ChannelLeaf, por exemplo) continua desenhando a linha quando existe.
const props = defineProps({
  folha: { type: Object, required: true },
  ativa: { type: Boolean, default: false },
  tema: { type: Object, required: true },
  neta: { type: Boolean, default: false },
});

const emit = defineEmits(['navegou']);

const temComponente = computed(
  () =>
    typeof props.folha.component === 'function' ||
    isVNode(props.folha.component)
);

const ir = (navegar, evento) => {
  navegar(evento);
  emit('navegou');
};
</script>

<template>
  <li class="min-w-0">
    <RouterLink v-slot="{ href, navigate }" :to="folha.to" custom>
      <a
        :href="href"
        :title="folha.label"
        :aria-current="ativa ? 'page' : undefined"
        class="flex items-center min-w-0 gap-2.5 pe-2 text-[0.9375rem] leading-5 transition-colors duration-150 rounded-lg min-h-11 motion-reduce:transition-none"
        :class="[
          neta ? 'ps-12' : 'ps-11',
          tema.foco,
          ativa ? tema.ativo : [tema.textoFilho, tema.passar],
        ]"
        @click="ir(navigate, $event)"
      >
        <component
          :is="folha.component"
          v-if="temComponente"
          v-bind="{
            label: folha.label,
            icon: folha.icon,
            active: ativa,
            badgeCount: folha.badgeCount,
          }"
        />
        <template v-else>
          <!-- Ícone só na lista que cresce (emoji do time, cor da etiqueta). No primeiro nível, o texto alinha com o
               do item pai e cabe inteiro em 240px ("Todas as conversas"). -->
          <span
            v-if="folha.icon && neta"
            class="grid shrink-0 size-4 place-content-center"
            aria-hidden="true"
          >
            <Icon :icon="folha.icon" class="size-4" />
          </span>
          <span class="flex-1 min-w-0 truncate">{{ folha.label }}</span>
          <ForkContador
            :numero="folha.badgeCount"
            :classes="ativa ? tema.contadorAtivo : tema.contador"
          />
        </template>
      </a>
    </RouterLink>
    <!-- #1809: na caixa de e-mail aberta, Escrever, Entrada, Spam e Lixeira embaixo dela. -->
    <PastasDoEmailNoMenu
      v-if="folha.to?.params?.inbox_id"
      :folha="folha"
      :tema="tema"
      @navegou="emit('navegou')"
    />
  </li>
</template>
