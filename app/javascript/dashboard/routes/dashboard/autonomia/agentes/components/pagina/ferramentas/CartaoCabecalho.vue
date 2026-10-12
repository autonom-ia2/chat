<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import FerramentaInterruptor from './FerramentaInterruptor.vue';
import { precisaRedigitar } from '../../../utils/ferramentas';

// #1301 (protótipos F06 e F10) — um cabeçalho da chamada. Ordem: nome → "É segredo" → valor, porque
// é o interruptor que transforma o valor em senha. Segredo já salvo aparece como "Guardado" (a API
// só devolve a máscara) e só troca digitando um novo.
// Defeito do backend (ToolsController#merged_tool_params casa o guardado pela chave): renomear o
// cabeçalho ou desligar "É segredo" perderia o valor guardado em silêncio. Por isso a tela avisa
// antes, abre o Valor vazio e o passo só salva com um valor novo.
const props = defineProps({
  cabecalho: { type: Object, required: true },
  indice: { type: Number, required: true },
  base: { type: String, required: true },
  erro: { type: String, default: '' },
  erroChave: { type: String, default: '' },
});

const emit = defineEmits(['update:cabecalho', 'remover']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.QUATRO';
const { t } = useI18n();

const EXEMPLO_DE_CHAVE = 'x-api-key';
const mostrar = ref(false);
const id = computed(() => `${props.base}-cab-${props.indice}`);
const preenchido = valor => String(valor ?? '').trim() !== '';
const quem = computed(() =>
  preenchido(props.cabecalho.chave)
    ? props.cabecalho.chave
    : t(`${NS}.ITEM`, { n: props.indice + 1 })
);

const redigitar = computed(() => precisaRedigitar(props.cabecalho));
const renomeado = computed(
  () =>
    props.cabecalho.guardado &&
    String(props.cabecalho.chave).trim() !== props.cabecalho.chaveOriginal
);
const mostraGuardado = computed(
  () =>
    props.cabecalho.segredo &&
    props.cabecalho.guardado &&
    !props.cabecalho.trocando &&
    !redigitar.value
);
const avisoRedigitar = computed(() => {
  if (renomeado.value) return t(`${NS}.RENOMEADO`);
  if (redigitar.value) return t(`${NS}.DESLIGOU`);
  return '';
});
const ajudaDaChave = computed(() => {
  if (mostraGuardado.value) return t(`${NS}.CHAVE_AJUDA_GUARDADO`);
  return preenchido(props.cabecalho.chave) ? '' : t(`${NS}.CHAVE_AJUDA`);
});

const mudar = mudanca =>
  emit('update:cabecalho', { ...props.cabecalho, ...mudanca });

// Religar "É segredo" com um valor já digitado conta como troca: o digitado vale, não o guardado.
const alternarSegredo = segredo => {
  mostrar.value = false;
  mudar({
    segredo,
    trocando: segredo && preenchido(props.cabecalho.valor),
  });
};

const trocarValor = () => mudar({ trocando: true, valor: '' });
</script>

<template>
  <div
    :data-cabecalho="indice"
    role="group"
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-4 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex items-center justify-between gap-2">
      <p
        :id="`${id}-titulo`"
        class="m-0 text-sm font-semibold break-all text-n-slate-12"
        :class="preenchido(cabecalho.chave) ? 'font-mono' : ''"
      >
        {{ preenchido(cabecalho.chave) ? cabecalho.chave : t(`${NS}.NOVO`) }}
      </p>
      <button
        type="button"
        data-remover
        :aria-label="
          t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.REMOVER_SR', { item: quem })
        "
        class="inline-flex items-center gap-1.5 px-2 text-sm rounded-lg min-h-11 shrink-0 text-n-slate-11 hover:text-n-ruby-11 hover:bg-n-alpha-2 focus-visible:text-n-ruby-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('remover')"
      >
        <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
        {{ t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.REMOVER') }}
      </button>
    </div>
    <FerramentaCampo
      :id="`${id}-chave`"
      :rotulo="t(`${NS}.CHAVE`)"
      :ajuda="ajudaDaChave"
      :erro="erroChave"
    >
      <template #default="{ descricao, invalido }">
        <FerramentaEntrada
          :id="`${id}-chave`"
          data-campo-chave
          :model-value="cabecalho.chave"
          mono
          :placeholder="EXEMPLO_DE_CHAVE"
          :descricao="descricao"
          :invalido="invalido"
          @update:model-value="mudar({ chave: $event })"
        />
      </template>
    </FerramentaCampo>
    <div class="flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <FerramentaInterruptor
          data-segredo
          :ligado="cabecalho.segredo"
          :rotulo="t(`${NS}.SEGREDO_SR`, { item: quem })"
          @alternar="alternarSegredo"
        />
        <span aria-hidden="true" class="text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.SEGREDO`) }}
        </span>
      </div>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.SEGREDO_AJUDA`) }}</p>
    </div>
    <FerramentaFaixa v-if="avisoRedigitar" data-redigitar tom="ambar">
      <p class="m-0">{{ avisoRedigitar }}</p>
    </FerramentaFaixa>
    <div v-if="mostraGuardado" data-guardado class="flex flex-col gap-1.5">
      <p class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.VALOR`) }}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 px-2.5 py-1 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-12"
        >
          <span aria-hidden="true" class="i-lucide-lock size-4" />
          {{ t(`${NS}.GUARDADO`) }}
        </span>
        <button
          type="button"
          data-trocar-valor
          :aria-label="t(`${NS}.TROCAR_SR`, { item: quem })"
          class="px-2 text-sm font-semibold underline rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="trocarValor"
        >
          {{ t(`${NS}.TROCAR`) }}
        </button>
      </div>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.GUARDADO_AJUDA`) }}</p>
    </div>
    <FerramentaCampo
      v-else
      :id="`${id}-valor`"
      :rotulo="t(`${NS}.VALOR`)"
      :erro="erro"
      :ajuda="cabecalho.segredo ? t(`${NS}.VALOR_AJUDA_SEGREDO`) : ''"
    >
      <template #default="{ descricao, invalido }">
        <div class="flex items-start gap-2">
          <FerramentaEntrada
            :id="`${id}-valor`"
            data-campo-valor
            :model-value="cabecalho.valor"
            mono
            :tipo="cabecalho.segredo && !mostrar ? 'password' : 'text'"
            :segredo="cabecalho.segredo"
            :descricao="descricao"
            :invalido="invalido"
            @update:model-value="mudar({ valor: $event })"
          />
          <AgenteBotao
            v-if="cabecalho.segredo"
            data-mostrar
            variante="contorno"
            class="shrink-0"
            :aria-label="
              mostrar
                ? t(`${NS}.ESCONDER_SR`, { item: quem })
                : t(`${NS}.MOSTRAR_SR`, { item: quem })
            "
            @click="mostrar = !mostrar"
          >
            {{ mostrar ? t(`${NS}.ESCONDER`) : t(`${NS}.MOSTRAR`) }}
          </AgenteBotao>
        </div>
      </template>
    </FerramentaCampo>
  </div>
</template>
