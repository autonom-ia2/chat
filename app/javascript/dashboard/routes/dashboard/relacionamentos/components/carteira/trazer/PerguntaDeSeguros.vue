<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2897 — a pergunta que só a conta de seguros vê, quando a planilha tem número
// de apólice: ela tem os seguros dos clientes? Uma pergunta, um toque: cada
// resposta já segue adiante. Com "Sim", quem tem seguro vira cliente desde o
// começo do seguro mais antigo, e a pergunta "já são clientes?" não aparece.
const emit = defineEmits(['temSeguros', 'soPessoas', 'voltar']);

const { t } = useI18n();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.TRAZER.PLANILHA.${chave}`);
</script>

<template>
  <section data-carteira="pergunta-seguros" class="flex flex-col gap-8">
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ tp('PERGUNTA') }}
    </h1>
    <div class="flex flex-wrap items-center gap-3">
      <Button
        data-carteira="tem-seguros"
        size="lg"
        :label="tp('TEM_SEGUROS')"
        @click="emit('temSeguros')"
      />
      <Button
        slate
        faded
        data-carteira="so-pessoas"
        size="lg"
        :label="tp('SO_PESSOAS')"
        @click="emit('soPessoas')"
      />
      <Button
        slate
        ghost
        size="lg"
        :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
        @click="emit('voltar')"
      />
    </div>
  </section>
</template>
