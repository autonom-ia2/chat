<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatarReais } from '../../ficha/formatos';
import { useIdioma } from '../../ficha/idioma';
import { situacaoDeCardConhecida } from '../../ficha/rotulos';
import GavetaLateral from './GavetaLateral.vue';

// #2894 — o resumo do card numa gaveta, com "Abrir no CRM". `card` nulo = fechada.
// Sem valor (`null`, de quem não pode ver valor) a linha do valor não existe.
const props = defineProps({
  card: { type: Object, default: null },
});
const emit = defineEmits(['fechar', 'abrirNoCrm']);

const { t } = useI18n();
const idioma = useIdioma();
const ra = chave => t(`RELACIONAMENTOS_FICHA.CARDS.GAVETA.${chave}`);

const linhas = computed(() => {
  const { card } = props;
  if (!card) return [];
  const situacao = situacaoDeCardConhecida(card.situacao);
  return [
    ['FUNIL', card.funil],
    ['ETAPA', card.etapa],
    ...(card.valor === null
      ? []
      : [['VALOR', formatarReais(card.valor, idioma.value)]]),
    ['SITUACAO', t(`RELACIONAMENTOS_FICHA.CARDS.SITUACAO.${situacao}`)],
  ];
});
</script>

<template>
  <GavetaLateral
    marca="gaveta-card"
    :aberta="Boolean(card)"
    :titulo="card?.titulo ?? ''"
    @fechar="emit('fechar')"
  >
    <dl class="grid gap-4 m-0">
      <div v-for="[chave, valor] in linhas" :key="chave">
        <dt class="text-sm text-n-slate-11">{{ ra(chave) }}</dt>
        <dd class="m-0 text-lg tabular-nums text-n-slate-12">{{ valor }}</dd>
      </div>
    </dl>
    <template #rodape>
      <Button
        data-foco
        size="lg"
        icon="i-lucide-external-link"
        :label="ra('ABRIR_NO_CRM')"
        @click="emit('abrirNoCrm')"
      />
    </template>
  </GavetaLateral>
</template>
