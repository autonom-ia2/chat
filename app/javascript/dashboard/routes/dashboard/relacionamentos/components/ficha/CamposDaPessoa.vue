<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import { REDES, nomeDaInformacao } from '../../ficha/informacoes';
import CampoDeTexto from './CampoDeTexto.vue';

// #2894 — os campos da gaveta "Alterar informações". Não altera nada: cada
// mudança sobe por um evento e quem usa cria o formulário novo. As redes sociais
// ficam recolhidas atrás de um botão (rótulo na mesma margem dos campos; a seta
// vai depois do texto).
defineProps({
  formulario: { type: Object, required: true },
  erros: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['mudar', 'mudarRede', 'mudarExtra']);

const { t } = useI18n();
const redesAbertas = ref(false);
const idDasRedes = useId();
const ra = chave => t(`RELACIONAMENTOS_FICHA.GAVETA.${chave}`);
const mensagem = campo => (campo ? ra(`ERRO.${campo}`) : '');

const CAMPOS_DE_TEXTO = [
  { campo: 'nome', rotulo: 'NOME', foco: true },
  { campo: 'email', rotulo: 'EMAIL', tipo: 'email' },
  { campo: 'cpf', rotulo: 'CPF', modo: 'numeric' },
  { campo: 'cidade', rotulo: 'CIDADE' },
  { campo: 'empresa', rotulo: 'EMPRESA' },
];
</script>

<template>
  <form class="flex flex-col gap-5" novalidate @submit.prevent>
    <template v-for="item in CAMPOS_DE_TEXTO" :key="item.campo">
      <CampoDeTexto
        :model-value="formulario[item.campo]"
        :rotulo="ra(item.rotulo)"
        :type="item.tipo || 'text'"
        :inputmode="item.modo"
        :data-foco="item.foco ? '' : undefined"
        :erro="mensagem(erros[item.campo])"
        @update:model-value="valor => emit('mudar', item.campo, valor)"
      />
      <CampoDeTelefone
        v-if="item.campo === 'nome'"
        :model-value="formulario.telefone"
        :label="ra('TELEFONE')"
        :rotulo-do-pais="ra('PAIS')"
        @update:model-value="valor => emit('mudar', 'telefone', valor)"
      />
    </template>

    <div class="flex flex-col gap-4">
      <button
        type="button"
        data-relacionamentos="redes-sociais"
        :aria-expanded="redesAbertas ? 'true' : 'false'"
        :aria-controls="idDasRedes"
        class="inline-flex items-center gap-2 p-0 text-base font-medium bg-transparent border-0 text-start min-h-11 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="redesAbertas = !redesAbertas"
      >
        {{ ra('REDES') }}
        <span
          class="size-4 i-lucide-chevron-right rtl:rotate-180"
          :class="{ 'rotate-90 rtl:rotate-90': redesAbertas }"
          aria-hidden="true"
        />
      </button>
      <div v-show="redesAbertas" :id="idDasRedes" class="flex flex-col gap-4">
        <CampoDeTexto
          v-for="rede in REDES"
          :key="rede"
          :model-value="formulario.redes[rede]"
          :rotulo="ra(`REDE.${rede}`)"
          @update:model-value="valor => emit('mudarRede', rede, valor)"
        />
      </div>
    </div>

    <template v-if="Object.keys(formulario.extras).length">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ ra('OUTRAS') }}
      </h3>
      <CampoDeTexto
        v-for="(valor, chave) in formulario.extras"
        :key="chave"
        :model-value="valor"
        :rotulo="nomeDaInformacao(chave)"
        @update:model-value="novo => emit('mudarExtra', chave, novo)"
      />
    </template>
  </form>
</template>
