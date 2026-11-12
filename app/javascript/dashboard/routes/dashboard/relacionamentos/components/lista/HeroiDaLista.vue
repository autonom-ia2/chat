<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { ACOES_DO_HEROI, escolherFrase } from '../../lista/fraseDoHeroi';

// #2894 — o herói da lista: a frase do dia (escolhida por `escolherFrase`) e
// UMA ação principal. "Trazer minha lista" fica discreto, ao lado dela, quando
// não é a principal (igual às duas ações do Pronto).
const props = defineProps({
  resumo: { type: Object, required: true },
  aba: { type: String, default: 'pessoas' },
  // Quem não pode trazer uma lista não vê o convite (nem como ação principal).
  podeTrazer: { type: Boolean, default: true },
});
const emit = defineEmits(['trazer', 'verGrupo']);

const { t } = useI18n();

const frase = computed(() => escolherFrase(props.resumo, props.aba));
const texto = computed(() =>
  frase.value.partes
    .map(({ chave, count }) =>
      count === undefined ? t(chave) : t(chave, { count }, count)
    )
    .join(' ')
);

const acaoPrincipal = computed(() => {
  const acao = frase.value.principal;
  const ehTrazer = acao?.acao === ACOES_DO_HEROI.TRAZER;
  return ehTrazer && !props.podeTrazer ? null : acao;
});
const trazerDiscreto = computed(
  () => frase.value.mostraTrazerDiscreto && props.podeTrazer
);

const principal = () => {
  const { acao, grupo } = acaoPrincipal.value;
  if (acao === ACOES_DO_HEROI.TRAZER) emit('trazer');
  else emit('verGrupo', grupo);
};
</script>

<template>
  <HeroiEscuro>
    <template #frase>{{ texto }}</template>
    <template v-if="frase.id === 'vazia'" #apoio>
      {{ t('RELACIONAMENTOS.LISTA.HEROI.VAZIA_APOIO') }}
    </template>
    <template v-if="acaoPrincipal || trazerDiscreto" #acao>
      <Button
        v-if="acaoPrincipal"
        size="lg"
        class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi"
        data-relacionamentos="heroi-acao"
        :label="t(acaoPrincipal.rotulo)"
        @click="principal"
      />
      <Button
        v-if="trazerDiscreto"
        size="lg"
        class="!bg-white/10 !text-white/90 ring-1 ring-inset ring-white/20 hover:enabled:!bg-white/20 focus-visible:!bg-white/20 focus-visible:!outline-white dark:!bg-white/10 dark:!text-white/90"
        data-relacionamentos="heroi-trazer"
        :label="t('RELACIONAMENTOS.COMUM.TRAZER_MINHA_LISTA')"
        @click="emit('trazer')"
      />
    </template>
  </HeroiEscuro>
</template>
