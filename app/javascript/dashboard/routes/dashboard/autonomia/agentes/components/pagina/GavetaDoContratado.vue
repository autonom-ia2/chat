<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ContratadosAPI from 'dashboard/api/autonomia/contratados';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import DadosDaCorretoraForm from '../DadosDaCorretoraForm.vue';
import AcessoDaSeguradoraForm from './AcessoDaSeguradoraForm.vue';
import { erroDoContratado } from '../../utils/contratado';

// #3211 (Tarefa 28) — a gaveta do agente contratado (GAVETA.CONTRATADO), com uma de duas partes:
// - `acesso`: o login e a senha do portal da seguradora (AcessoDaSeguradoraForm, passo 2), a que abre por
//   `?gaveta=contratado` logo depois do Contratar;
// - `corretora`: o nome e a apresentação da corretora (mockup aprovado, estado 15, com só o "Salvar" `xl bloco`). O
//   nome do agente fica na gaveta de foto e nome; o servidor confere as três chaves juntas, então ele vai como está.
// `atualizado` pede à página que releia o agente (o bloco "Corretora e acesso" e o estado do acesso).
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  parte: {
    type: String,
    default: 'acesso',
    validator: v => ['acesso', 'corretora'].includes(v),
  },
  emConfiguracao: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'escolherCanal', 'atualizado']);

const { t } = useI18n();
const formulario = ref(null);
const salvando = ref(false);
const erro = ref(null);

const dados = computed(() => props.agente.contratado || {});
const inicial = computed(() => ({
  nomeCorretora: dados.value.nome_corretora || '',
  sobreCorretora: dados.value.sobre_corretora || '',
}));

const salvar = async campos => {
  if (salvando.value) return;
  salvando.value = true;
  erro.value = null;
  try {
    await ContratadosAPI.salvarDados(props.agente.id, {
      nomeAgente: dados.value.nome_agente,
      ...campos,
    });
  } catch (falha) {
    erro.value = erroDoContratado(t, falha);
    salvando.value = false;
    return;
  }
  salvando.value = false;
  useAlert(t('AGENTS.CONTRATADOS.CORRETORA.FEITO', { nome: props.nome }));
  emit('atualizado');
  emit('fechar');
};

// Esc e o clique fora não fecham com o que a pessoa mudou, nem enquanto salva (o X continua fechando).
const podeFechar = () => !salvando.value && !formulario.value?.temMudanca();
</script>

<template>
  <AcessoDaSeguradoraForm
    v-if="parte === 'acesso'"
    :agente="agente"
    :nome="nome"
    :em-configuracao="emConfiguracao"
    @fechar="emit('fechar')"
    @escolher-canal="emit('escolherCanal')"
    @conferido="emit('atualizado')"
  />
  <AgenteGaveta
    v-else
    :titulo="t('AGENTS.CONTRATADOS.CORRETORA.TITULO')"
    :pode-fechar="podeFechar"
    @fechar="emit('fechar')"
  >
    <DadosDaCorretoraForm
      ref="formulario"
      modo="editar"
      :inicial="inicial"
      :nome="nome"
      :ocupado="salvando"
      :erro="erro"
      @enviar="salvar"
    />
    <template #rodape>
      <AgenteBotao
        data-salvar-corretora
        tamanho="xl"
        bloco
        :carregando="salvando"
        @click="formulario?.enviar()"
      >
        {{ t('AGENTS.CONTRATADOS.CORRETORA.SALVAR') }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
