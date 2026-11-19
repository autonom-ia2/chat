<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { ABAS } from '../../../fonte/grupos';
import { ABA_SEGUROS } from '../../../fonte/gruposDeSeguros';

// #3057 — o caminho de volta de "Como trazer", "Trazer por PDFs" e "Do Agger",
// sempre no topo e com cara de botão (no celular, a outra saída era o ☰).
// `para="origem"` (Como trazer) volta à aba de onde a pessoa veio: a lista
// passa a aba no endereço (`?aba=`) ao abrir "Trazer", e as telas de dentro o
// carregam junto. Sem aba no endereço, é Pessoas, a aba que a lista abre.
// `para="como"` (PDFs e Agger) volta à pergunta "Como trazer", na mesma aba de
// origem, sem o lote ou a busca em andamento (eles continuam no histórico).
// #3057 (revisão) — `aba` fixa a aba de volta, para a tela que só tem uma
// origem ("Ajustar renovações" volta sempre para Seguros).
const props = defineProps({
  para: {
    type: String,
    default: 'origem',
    validator: valor => ['origem', 'como'].includes(valor),
  },
  aba: { type: String, default: '' },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const NOME_DA_ABA = {
  [ABAS.PESSOAS]: 'PESSOAS',
  [ABAS.EMPRESAS]: 'EMPRESAS',
  [ABA_SEGUROS]: 'SEGUROS',
};
const abaDeOrigem = computed(() => {
  const aba = props.aba || route.query.aba;
  return NOME_DA_ABA[aba] ? aba : ABAS.PESSOAS;
});
const naAbaDeOrigem = computed(() =>
  abaDeOrigem.value === ABAS.PESSOAS ? {} : { aba: abaDeOrigem.value }
);
const rotulo = computed(() =>
  props.para === 'como'
    ? t('RELACIONAMENTOS_CARTEIRA.VOLTAR.COMO')
    : t(`RELACIONAMENTOS_CARTEIRA.VOLTAR.${NOME_DA_ABA[abaDeOrigem.value]}`)
);

const voltar = () =>
  router.push(
    props.para === 'como'
      ? { name: 'relacionamentos_trazer', query: naAbaDeOrigem.value }
      : { name: 'relationships_home', query: naAbaDeOrigem.value }
  );
</script>

<template>
  <Button
    slate
    ghost
    icon="i-lucide-arrow-left"
    class="self-start -ms-3 !h-11"
    data-relacionamentos="voltar"
    :data-para="para"
    :label="rotulo"
    @click="voltar"
  />
</template>
