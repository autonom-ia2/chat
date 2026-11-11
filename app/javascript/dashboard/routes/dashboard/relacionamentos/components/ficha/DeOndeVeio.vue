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
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();
const idioma = useIdioma();

// Os canais que têm nome em RELACIONAMENTOS_FICHA.ORIGEM.CANAL_NOME.
const CANAIS_COM_NOME = ['whatsapp', 'email', 'instagram', 'site'];

const frase = computed(() => {
  const { origem } = props;
  if (!origem) return '';
  const data = formatarDiaMes(origem.quando, idioma.value, props.agora);
  if (origem.tipo === 'lista') {
    return t('RELACIONAMENTOS_FICHA.ORIGEM.LISTA', { nome: origem.nome, data });
  }
  // Canal que a lista não conhece: frase genérica, nunca a chave crua.
  if (!CANAIS_COM_NOME.includes(origem.canal)) {
    return t('RELACIONAMENTOS_FICHA.ORIGEM.CANAL_DESCONHECIDO', { data });
  }
  return t('RELACIONAMENTOS_FICHA.ORIGEM.CANAL', {
    canal: t(`RELACIONAMENTOS_FICHA.ORIGEM.CANAL_NOME.${origem.canal}`),
    data,
  });
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
