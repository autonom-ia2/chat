<script setup>
import { useI18n } from 'vue-i18n';
import { quandoRelativo } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import CartaoDaSecao from './CartaoDaSecao.vue';

// #2894 — o que foi trocado nas conversas: um ícone pelo tipo, o nome e quando.
defineProps({
  arquivos: { type: Array, required: true },
  agora: { type: Number, default: () => Date.now() },
});

const ICONES = {
  imagem: 'i-lucide-image',
  documento: 'i-lucide-file-text',
  audio: 'i-lucide-mic',
  video: 'i-lucide-video',
};

const { t } = useI18n();
const idioma = useIdioma();
const ra = chave => t(`RELACIONAMENTOS_FICHA.ARQUIVOS.${chave}`);
</script>

<template>
  <CartaoDaSecao :titulo="ra('TITULO')" data-relacionamentos="arquivos">
    <p v-if="!arquivos.length" class="m-0 text-base text-n-slate-11">
      {{ ra('VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="arquivo in arquivos"
        :key="arquivo.id"
        class="flex items-center gap-3"
      >
        <span
          class="flex items-center justify-center size-11 rounded-xl shrink-0 bg-n-alpha-2 text-n-slate-11"
          role="img"
          :aria-label="ra(`TIPO.${arquivo.tipo}`)"
        >
          <span class="size-5" :class="ICONES[arquivo.tipo]" />
        </span>
        <div class="min-w-0">
          <p class="m-0 text-base truncate text-n-slate-12">
            {{ arquivo.nome }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ quandoRelativo(arquivo.quando, agora, idioma) }}
          </p>
        </div>
      </li>
    </ul>
  </CartaoDaSecao>
</template>
