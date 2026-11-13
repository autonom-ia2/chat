<script setup>
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// #2897 — o aviso do que acabou de acontecer com o seguro, com "Desfazer"
// quando dá para voltar atrás. A região viva fica na tela desde o início (uma
// região que nasce junto com o texto não é anunciada); vazia, não ocupa espaço.
// O aviso fica até a próxima ação: desfazer não tem prazo.
defineProps({
  texto: { type: String, default: '' },
  podeDesfazer: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
});
const emit = defineEmits(['desfazer']);

const { t } = useI18n();
</script>

<template>
  <div data-carteira="aviso-vivo" role="status" aria-live="polite">
    <Banner v-if="texto" color="teal">
      <div class="flex flex-wrap items-center gap-3">
        <span class="text-sm">{{ texto }}</span>
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
      </div>
    </Banner>
  </div>
</template>
