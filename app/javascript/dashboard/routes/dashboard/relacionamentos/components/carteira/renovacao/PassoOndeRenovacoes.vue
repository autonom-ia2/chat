<script setup>
import { ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  AJUSTES_PADRAO,
  faltaEmOndeFicam,
} from '../../../carteira/ajustesDaRenovacao';
import OndeFicamAsRenovacoes from './OndeFicamAsRenovacoes.vue';

// #2897 — o passo "Onde ficam as renovações?", que aparece só na primeira vez
// que a conta traz seguros. Já vem respondido com o padrão: quem não quer
// decidir nada só continua. O botão fica sempre ligado; se falta algo, o clique
// diz o que é e leva o foco até lá. Quem não pode mexer em funis segue sem
// escolher.
const props = defineProps({
  funis: { type: Array, default: () => [] },
  vencimentos: { type: Array, default: () => [] },
  semPermissao: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher', 'voltar']);

const { t } = useI18n();
const to = chave => t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.ONDE.${chave}`);
const id = useId();
const escolha = ref({
  onde: AJUSTES_PADRAO.onde,
  funil: AJUSTES_PADRAO.funil,
  etapa: AJUSTES_PADRAO.etapa,
  dias: AJUSTES_PADRAO.dias,
});
const falta = ref('');
const peca = useTemplateRef('peca');

const continuar = () => {
  if (props.semPermissao) {
    emit('escolher', null);
    return;
  }
  falta.value = faltaEmOndeFicam(escolha.value);
  if (falta.value) peca.value?.focar(falta.value);
  else emit('escolher', escolha.value);
};

watch(escolha, () => {
  falta.value = '';
});
</script>

<template>
  <section data-carteira="onde-renovacoes" class="flex flex-col gap-8">
    <h1
      :id="`${id}-titulo`"
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ to('TITULO') }}
    </h1>
    <OndeFicamAsRenovacoes
      ref="peca"
      v-model="escolha"
      :funis="funis"
      :vencimentos="vencimentos"
      :sem-permissao="semPermissao"
      :falta="falta"
      :id-do-aviso="`${id}-falta`"
      :rotulo-id="`${id}-titulo`"
    />
    <p
      v-if="falta"
      :id="`${id}-falta`"
      data-carteira="falta-nas-renovacoes"
      role="alert"
      class="m-0 text-base font-medium text-n-ruby-11"
    >
      {{ to(`FALTA.${falta}`) }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        data-carteira="continuar-renovacoes"
        size="lg"
        :is-loading="ocupado"
        :disabled="ocupado"
        :label="
          semPermissao
            ? to('SEGUIR_SEM_ESCOLHER')
            : t('RELACIONAMENTOS.COMUM.CONTINUAR')
        "
        @click="continuar"
      />
      <Button
        slate
        faded
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
        @click="emit('voltar')"
      />
    </div>
  </section>
</template>
