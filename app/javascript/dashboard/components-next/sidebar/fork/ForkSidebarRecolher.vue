<script setup>
import { computed, onBeforeUnmount, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ForkDica from './ForkDica.vue';

// Botão fixo no pé do menu novo (#1617): "Recolher menu" aberto; recolhido vira ícone com a dica "Abrir menu".
// É sempre o mesmo botão, então o foco fica nele ao alternar. O atalho Ctrl/Cmd+\ aparece na dica.
const props = defineProps({
  recolhido: { type: Boolean, default: false },
  controla: { type: String, required: true },
  tema: { type: Object, required: true },
  // Recolher sozinho (#1781): 1 = barra cheia, 0 = sem barra. Com movimento reduzido a barra fica parada.
  progresso: { type: Number, default: 0 },
  semAnimacao: { type: Boolean, default: false },
});

const emit = defineEmits(['alternar']);

const { t } = useI18n();
const ehMac =
  typeof navigator !== 'undefined' &&
  (navigator.userAgentData?.platform || navigator.platform || '').includes(
    'Mac'
  );
const tecla = ehMac ? '⌘ \\' : 'Ctrl \\';

const rotulo = computed(() =>
  t(props.recolhido ? 'FORK_SIDEBAR.ABRIR_MENU' : 'FORK_SIDEBAR.RECOLHER')
);
const textoDaDica = computed(() =>
  t('FORK_SIDEBAR.ACAO_COM_ATALHO', { acao: rotulo.value, tecla })
);

const idDaDica = `fork-dica-recolher-${useId()}`;
const botao = ref(null);
const retangulo = ref({ top: 0, left: 0, bottom: 0, right: 0 });
const dicaVisivel = ref(false);
let relogio = null;
const mostrar = () => {
  clearTimeout(relogio);
  relogio = setTimeout(() => {
    const caixa = botao.value?.getBoundingClientRect();
    if (caixa) retangulo.value = caixa;
    dicaVisivel.value = true;
  }, 300);
};
const esconder = () => {
  clearTimeout(relogio);
  dicaVisivel.value = false;
};
onBeforeUnmount(() => clearTimeout(relogio));

const alternar = () => {
  esconder();
  emit('alternar');
};
</script>

<template>
  <li class="max-md:hidden">
    <button
      ref="botao"
      type="button"
      data-recolher-menu
      :aria-expanded="!recolhido"
      :aria-controls="controla"
      :aria-label="recolhido ? rotulo : undefined"
      :aria-describedby="idDaDica"
      class="relative flex items-center gap-3 text-[0.9375rem] leading-5 transition-colors duration-150 min-h-11 rounded-xl motion-reduce:transition-none"
      :class="[
        tema.foco,
        tema.textoFilho,
        tema.passar,
        recolhido ? 'size-11 justify-center' : 'w-full px-3',
      ]"
      @click="alternar"
      @mouseenter="mostrar"
      @mouseleave="esconder"
      @focus="mostrar"
      @blur="esconder"
      @keydown.esc="esconder"
    >
      <span
        class="size-5 shrink-0"
        :class="
          recolhido ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'
        "
        aria-hidden="true"
      />
      <template v-if="!recolhido">
        <span class="flex-1 min-w-0 truncate text-start">{{ rotulo }}</span>
        <span
          v-if="progresso > 0"
          data-barra-recolher
          aria-hidden="true"
          class="absolute bottom-1 h-0.5 overflow-hidden rounded-full pointer-events-none inset-x-3"
          :class="tema.trilho"
        >
          <span
            class="block h-full origin-left rtl:origin-right"
            :class="[
              tema.progresso,
              semAnimacao
                ? ''
                : 'transition-transform duration-100 ease-linear',
            ]"
            :style="{ transform: `scaleX(${semAnimacao ? 1 : progresso})` }"
          />
        </span>
      </template>
    </button>
    <ForkDica
      :id="idDaDica"
      :texto="textoDaDica"
      :visivel="dicaVisivel && recolhido"
      :retangulo="retangulo"
    />
  </li>
</template>
