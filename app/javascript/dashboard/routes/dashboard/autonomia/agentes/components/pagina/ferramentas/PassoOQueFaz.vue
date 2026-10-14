<script setup>
import { useI18n } from 'vue-i18n';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';

// #1301 (protótipo F03) — passo 1: nome e "Quando usar", o campo que mais decide se a ferramenta
// funciona. "Começar de um exemplo" preenche os 4 passos com um exemplo genérico.
const props = defineProps({
  rascunho: { type: Object, required: true },
  base: { type: String, required: true },
  erros: { type: Object, required: true },
  avisarQuando: { type: Boolean, default: false },
  podeUsarExemplo: { type: Boolean, default: false },
  exemploAplicado: { type: Boolean, default: false },
});

const emit = defineEmits(['update:rascunho', 'exemplo']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.UM';
const { t } = useI18n();

const mudar = (campo, valor) =>
  emit('update:rascunho', { ...props.rascunho, [campo]: valor });
const preenchido = valor => String(valor ?? '').trim() !== '';
</script>

<template>
  <div class="flex flex-col gap-5">
    <FerramentaFaixa v-if="exemploAplicado" data-exemplo-aplicado tom="azul">
      <p class="m-0">{{ t(`${NS}.EXEMPLO_APLICADO`) }}</p>
    </FerramentaFaixa>
    <FerramentaCampo
      :id="`${base}-nome`"
      :rotulo="t(`${NS}.NOME`)"
      :erro="erros.nome ? t(`${NS}.NOME_ERRO`) : ''"
      :ajuda="
        preenchido(rascunho.nome)
          ? t(`${NS}.NOME_AJUDA`)
          : t(`${NS}.NOME_AJUDA_VAZIO`)
      "
    >
      <template #default="{ descricao, invalido }">
        <FerramentaEntrada
          :id="`${base}-nome`"
          data-campo-nome
          :model-value="rascunho.nome"
          :descricao="descricao"
          :invalido="invalido"
          @update:model-value="mudar('nome', $event)"
        />
      </template>
    </FerramentaCampo>
    <FerramentaCampo
      :id="`${base}-quando`"
      :rotulo="t(`${NS}.QUANDO`)"
      :ajuda="t(`${NS}.QUANDO_AJUDA`)"
      :exemplo="t(`${NS}.QUANDO_EXEMPLO`)"
      :preenchido="preenchido(rascunho.quando)"
    >
      <template #default="{ descricao }">
        <FerramentaEntrada
          :id="`${base}-quando`"
          data-campo-quando
          :model-value="rascunho.quando"
          :linhas="4"
          :descricao="descricao"
          @update:model-value="mudar('quando', $event)"
        />
      </template>
      <template #depois>
        <FerramentaFaixa
          v-if="avisarQuando"
          data-aviso-quando
          tom="ambar"
          solta
        >
          <p class="m-0">{{ t(`${NS}.QUANDO_AVISO`) }}</p>
        </FerramentaFaixa>
      </template>
    </FerramentaCampo>
    <p v-if="podeUsarExemplo" class="m-0">
      <button
        type="button"
        data-usar-exemplo
        class="inline-flex items-center gap-2 px-1 text-sm font-semibold underline rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('exemplo')"
      >
        <span aria-hidden="true" class="i-lucide-file-text size-4" />
        {{ t(`${NS}.EXEMPLO`) }}
      </button>
    </p>
  </div>
</template>
