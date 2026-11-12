<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';

// #2881 — a frase "Use quando" de uma ferramenta pronta que o agente já tem, com "Alterar quando usar". É a frase que
// o agente lê para decidir a hora de usar a ferramenta: antes ela só era gravada no "Incluir" da vitrine, e mudar
// pedia tirar e incluir de novo. O campo é o mesmo do "Incluir" (VitrineDetalhe): até 500 letras, e vazio não salva.
// `salvar(frase)` é de quem chama e diz se gravou: a edição só fecha quando gravou, para o texto não se perder.
// O slot fica ao lado do botão: as outras ações da linha (o "Tirar").
const props = defineProps({
  // O que a linha mostra (a frase da conta ou, sem ela, o que a ferramenta faz).
  frase: { type: String, required: true },
  // O texto que abre a edição (a frase da conta ou, sem ela, a frase padrão da ferramenta).
  quando: { type: String, required: true },
  ferramenta: { type: String, required: true },
  salvar: { type: Function, required: true },
});

const NS = 'AGENTS.VITRINE';
const MAXIMO_DE_LETRAS = 500;
const { t } = useI18n();
const campoId = `pronta-quando-${useId()}`;

const editando = ref(false);
const rascunho = ref('');
const salvando = ref(false);
const erro = ref('');
const botao = ref(null);

const abrir = async () => {
  rascunho.value = props.quando;
  erro.value = '';
  editando.value = true;
  await nextTick();
  document.getElementById(campoId)?.focus();
};
const fechar = async () => {
  editando.value = false;
  await nextTick();
  botao.value?.$el?.focus();
};
const confirmar = async () => {
  const frase = rascunho.value.trim();
  if (!frase) {
    erro.value = t(`${NS}.DETALHE.QUANDO_VAZIO`);
    document.getElementById(campoId)?.focus();
    return;
  }
  if (salvando.value) return;
  salvando.value = true;
  const gravou = await props.salvar(frase);
  salvando.value = false;
  if (gravou) fechar();
};
</script>

<template>
  <div v-if="editando" data-pronta-quando class="flex flex-col gap-2 pt-1">
    <label :for="campoId" class="text-sm font-semibold text-n-slate-12">
      {{ t(`${NS}.DETALHE.QUANDO`) }}
    </label>
    <p :id="`${campoId}-ajuda`" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.DETALHE.QUANDO_AJUDA`) }}
    </p>
    <textarea
      :id="campoId"
      v-model="rascunho"
      rows="3"
      :maxlength="MAXIMO_DE_LETRAS"
      :aria-describedby="`${campoId}-ajuda`"
      :aria-invalid="erro ? 'true' : undefined"
      class="w-full px-3 py-2.5 !mb-0 text-base border-0 resize-y rounded-xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 focus:ring-2 focus:ring-n-blue-11"
      @input="erro = ''"
    />
    <p v-if="erro" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ erro }}
    </p>
    <div class="flex flex-wrap gap-2">
      <AgenteBotao data-salvar-quando :carregando="salvando" @click="confirmar">
        {{ t(`${NS}.PRONTAS.QUANDO_SALVAR`) }}
      </AgenteBotao>
      <AgenteBotao
        data-cancelar-quando
        variante="fantasma"
        :desabilitado="salvando"
        @click="fechar"
      >
        {{ t(`${NS}.PRONTAS.QUANDO_CANCELAR`) }}
      </AgenteBotao>
    </div>
  </div>
  <template v-else>
    <span data-frase class="text-sm text-n-slate-11 line-clamp-2">
      {{ frase }}
    </span>
    <div class="flex flex-wrap items-center gap-1 -ms-4">
      <AgenteBotao
        ref="botao"
        data-alterar-quando
        variante="fantasma"
        :aria-label="t(`${NS}.PRONTAS.QUANDO_ALTERAR_SR`, { ferramenta })"
        @click="abrir"
      >
        {{ t(`${NS}.PRONTAS.QUANDO_ALTERAR`) }}
      </AgenteBotao>
      <slot />
    </div>
  </template>
</template>
