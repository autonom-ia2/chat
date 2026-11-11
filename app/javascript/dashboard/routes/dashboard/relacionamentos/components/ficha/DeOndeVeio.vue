<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatarDiaMes } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import CartaoDaSecao from './CartaoDaSecao.vue';

// #2894 — "De onde veio": a lista de onde a pessoa foi trazida ou o canal por
// onde ela chegou, e quando.
const props = defineProps({
  origem: { type: Object, default: null },
});

const { t } = useI18n();
const idioma = useIdioma();

const frase = computed(() => {
  const { origem } = props;
  if (!origem) return '';
  const data = formatarDiaMes(origem.quando, idioma.value);
  if (origem.tipo === 'lista') {
    return t('RELACIONAMENTOS_FICHA.ORIGEM.LISTA', { nome: origem.nome, data });
  }
  const canal = t(`RELACIONAMENTOS_FICHA.ORIGEM.CANAL_NOME.${origem.canal}`);
  return t('RELACIONAMENTOS_FICHA.ORIGEM.CANAL', { canal, data });
});
</script>

<template>
  <CartaoDaSecao
    v-if="origem"
    data-relacionamentos="de-onde-veio"
    :titulo="t('RELACIONAMENTOS_FICHA.ORIGEM.TITULO')"
  >
    <p class="m-0 text-base text-n-slate-12">{{ frase }}</p>
  </CartaoDaSecao>
</template>
