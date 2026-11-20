<script setup>
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2897 — o aviso do que acabou de acontecer com o seguro, com "Desfazer"
// quando dá para voltar atrás. A região viva fica na tela desde o início (uma
// região que nasce junto com o texto não é anunciada); vazia, não ocupa espaço.
// O aviso fica até a próxima ação: desfazer não tem prazo.
// #3071 — com `podeFechar` (a ficha da pessoa) ganha um × de 44 px que emite
// `fechar`: quem lê o aviso tira ele da frente sem fazer outra coisa.
defineProps({
  texto: { type: String, default: '' },
  podeDesfazer: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
  podeFechar: { type: Boolean, default: false },
});
const emit = defineEmits(['desfazer', 'fechar']);

const { t } = useI18n();
</script>

<template>
  <div data-carteira="aviso-vivo" role="status" aria-live="polite">
    <Banner
      v-if="texto"
      color="teal"
      class="[&>div:first-child]:flex-1 [&>div:first-child]:min-w-0"
    >
      <div class="flex flex-wrap items-center gap-3">
        <span class="flex-1 min-w-0 text-sm">{{ texto }}</span>
        <Button
          v-if="podeDesfazer"
          slate
          faded
          size="lg"
          data-carteira="desfazer"
          :is-loading="desfazendo"
          :label="t('RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.DESFAZER')"
          @click="emit('desfazer')"
        />
        <button
          v-if="podeFechar"
          type="button"
          data-carteira="fechar-aviso"
          class="inline-flex items-center justify-center -me-2 rounded-lg size-11 shrink-0 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t('RELACIONAMENTOS.COMUM.FECHAR_AVISO')"
          @click="emit('fechar')"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </div>
    </Banner>
  </div>
</template>
