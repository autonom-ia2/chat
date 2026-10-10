<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';

// #1181 PR3 — confirmação com espera e erro no lugar (protótipo confirmFlow: T13, T15, T16, tirar
// arquivo, não atender em nenhum lugar). Usa o Dialog do produto (<dialog> nativo: prende o foco,
// fecha no Esc e devolve o foco a quem abriu) com os botões AA do módulo no rodapé.
// `executar` é uma função assíncrona: enquanto roda, o botão espera; se falha, o erro padrão
// (T17) aparece dentro do diálogo com "Tentar de novo" e o botão de confirmar sai (uma ação só).
// Sem `executar`, confirmar só fecha e avisa (`confirmado`).
// variante 'aviso' (T14, ação sem volta): o texto vai numa caixa âmbar com ícone e o botão de
// confirmar fica âmbar. O slot padrão entra depois do texto (ex.: o atalho do T16 para Parar).

const props = defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  extra: { type: String, default: '' },
  confirmar: { type: String, required: true },
  rotuloCarregando: { type: String, default: '' },
  variante: {
    type: String,
    default: 'primario',
    validator: v => ['primario', 'perigo', 'aviso'].includes(v),
  },
  cancelar: { type: String, default: '' },
  erroTitulo: { type: String, default: '' },
  erroGarantia: { type: String, default: '' },
  executar: { type: Function, default: null },
});

const emit = defineEmits(['confirmado', 'fechada']);

const { t } = useI18n();
const aviso = computed(() => props.variante === 'aviso');
const dialogo = ref(null);
const rodando = ref(false);
const falhou = ref(false);

const abrir = () => {
  falhou.value = false;
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

const aoFechar = () => {
  rodando.value = false;
  falhou.value = false;
  emit('fechada');
};

const confirmarAgora = async () => {
  if (rodando.value) return;
  if (!props.executar) {
    fechar();
    emit('confirmado');
    return;
  }
  rodando.value = true;
  try {
    await props.executar();
    rodando.value = false;
    fechar();
    emit('confirmado');
  } catch {
    rodando.value = false;
    falhou.value = true;
  }
};

defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="md"
    :title="titulo"
    :description="aviso ? '' : texto"
    @close="aoFechar"
  >
    <div
      v-if="aviso && texto"
      data-aviso
      class="flex items-start gap-3 p-4 text-sm rounded-xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
    >
      <span
        class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <p class="m-0">{{ texto }}</p>
    </div>
    <p v-if="extra" data-extra class="m-0 text-sm text-n-slate-11">
      {{ extra }}
    </p>
    <slot />
    <AgenteErro
      v-if="falhou"
      data-erro
      :titulo="erroTitulo"
      :garantia="erroGarantia"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      :carregando="rodando"
      @acao="confirmarAgora"
    />
    <template #footer>
      <div data-botoes class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          data-cancelar
          variante="contorno"
          :desabilitado="rodando"
          @click="fechar"
        >
          {{ cancelar || t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          v-if="!falhou"
          data-confirmar
          :variante="variante"
          :carregando="rodando"
          :rotulo-carregando="rotuloCarregando"
          @click="confirmarAgora"
        >
          {{ confirmar }}
        </AgenteBotao>
      </div>
    </template>
  </Dialog>
</template>
