<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { linhasDosCampos } from '../../ficha/atributos';
import CartaoDaSecao from './CartaoDaSecao.vue';
import ListaDeInformacoes from './ListaDeInformacoes.vue';

// #3082 — o bloco "Seus campos" da ficha da pessoa e da empresa, no topo da
// coluna do lado: os campos que a conta criou e que aparecem na ficha (os
// escolhidos em "Escolher campos da ficha" e os que já têm valor). Campo sem
// valor aparece com "Não informado". `campos` vem de
// ficha/atributos.js#camposDoRegistro (todos os da conta, com `principal`).
// Quem pode mudar (`podeEditar`) tem "Alterar" no topo. Quem pode mudar os
// campos da ficha (`podeEscolherCampos`) cria um campo novo e escolhe quais
// aparecem, ali mesmo. Quem usa decide se o bloco aparece
// (ficha/atributos.js#blocoDosCamposAparece).
const props = defineProps({
  campos: { type: Array, required: true },
  // 'pessoa' ou 'empresa': muda o exemplo da frase de vazio.
  de: { type: String, default: 'pessoa' },
  podeEditar: { type: Boolean, default: true },
  podeEscolherCampos: { type: Boolean, default: false },
});
const emit = defineEmits(['alterar', 'escolherCampos', 'criarCampo']);

const { t } = useI18n();
const rc = chave => t(`RELACIONAMENTOS_FICHA.CAMPOS.${chave}`);

const linhas = computed(() => linhasDosCampos(props.campos));
const podeMexer = computed(() => props.podeEditar && props.podeEscolherCampos);
const semCampos = computed(() => props.campos.length === 0);
const vazio = computed(() =>
  semCampos.value
    ? rc(props.de === 'empresa' ? 'SEM_CAMPOS_EMPRESA' : 'SEM_CAMPOS_PESSOA')
    : rc('NENHUM_NA_FICHA')
);
</script>

<template>
  <CartaoDaSecao :titulo="rc('TITULO')" data-relacionamentos="seus-campos">
    <template v-if="podeEditar && linhas.length" #acao>
      <Button
        data-relacionamentos="alterar-campos"
        slate
        faded
        :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ALTERAR')"
        :aria-label="rc('ALTERAR')"
        @click="emit('alterar')"
      />
    </template>
    <ListaDeInformacoes
      v-if="linhas.length"
      :linhas="linhas"
      :com-frase-de-vazio="false"
    />
    <p v-else data-vazio class="m-0 text-base text-n-slate-11">
      {{ vazio }}
    </p>
    <div
      v-if="podeMexer"
      class="flex flex-wrap mt-4 gap-x-2 gap-y-1"
      :class="{ '-ms-3': !semCampos }"
    >
      <Button
        data-relacionamentos="criar-campo"
        :variant="semCampos ? 'solid' : 'ghost'"
        :color="semCampos ? 'blue' : 'slate'"
        icon="i-lucide-plus"
        class="!h-11"
        :label="rc(semCampos ? 'PRIMEIRO' : 'NOVO')"
        @click="emit('criarCampo')"
      />
      <Button
        v-if="!semCampos"
        data-relacionamentos="escolher-campos"
        slate
        ghost
        icon="i-lucide-settings-2"
        class="!h-11"
        :label="rc('ESCOLHER')"
        @click="emit('escolherCampos')"
      />
    </div>
  </CartaoDaSecao>
</template>
