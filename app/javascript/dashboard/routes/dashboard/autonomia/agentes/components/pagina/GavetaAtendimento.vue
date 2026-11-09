<script setup>
import { ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import DadosDoAtendimento from './DadosDoAtendimento.vue';
import {
  lerAtendimento,
  recusaDoServidor,
  useSalvarAtendimento,
} from '../../composables/useDadosDoAtendimento';

// #1479 (opção B do Rodrigo) — "Endereço e telefone de {nome}": gaveta curta do bloco próprio da página, nos dois
// modos (manual e conversando). Só os dois campos, Salvar e Cancelar; o foco fica preso na AgenteGaveta. Telefone
// incompleto não salva: leva ao campo com o aviso. Fechar sem salvar não grava nada.
// Grava no servidor (`config.atendimento`). A recusa vai ao campo pelo ATRIBUTO do 422 (`telefone`, `endereco`), com
// o aviso da própria tela; recusa de outro atributo ou falha de rede: o aviso de erro no rodapé, com "Tentar de novo".
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.ATENDIMENTO';
const base = `atendimento-${useId()}`;

const inicial = lerAtendimento(props.agente);
const endereco = ref(inicial.endereco);
const telefone = ref(inicial.telefone);
const campos = ref(null);
const conferir = ref(false);
const falhou = ref(false);
const tituloDoErro = ref('');
const erroDoTelefone = ref('');
const erroDoEndereco = ref('');
const { salvando, salvar: gravar } = useSalvarAtendimento();

// Mexeu no campo: a recusa anterior do servidor não vale mais.
watch(telefone, () => {
  erroDoTelefone.value = '';
});
watch(endereco, () => {
  erroDoEndereco.value = '';
});

const mostrarRecusa = falha => {
  const recusa = recusaDoServidor(falha);
  const atributos = recusa?.atributos || [];
  const doTelefone = atributos.includes('telefone');
  const doEndereco = atributos.includes('endereco');
  if (doTelefone || doEndereco) {
    if (doEndereco) erroDoEndereco.value = t(`${NS}.CAMPOS.ENDERECO_RECUSADO`);
    if (doTelefone) {
      erroDoTelefone.value = t(`${NS}.CAMPOS.TELEFONE_RECUSADO`);
      campos.value?.focarTelefone();
    }
    return;
  }
  tituloDoErro.value = recusa?.mensagem || t(`${NS}.ERRO`);
  falhou.value = true;
};

const salvar = async () => {
  if (salvando.value) return;
  if (campos.value?.incompleto) {
    conferir.value = true;
    campos.value.focarTelefone();
    return;
  }
  falhou.value = false;
  erroDoTelefone.value = '';
  erroDoEndereco.value = '';
  try {
    await gravar(props.agente, {
      endereco: endereco.value,
      telefone: telefone.value,
    });
    useAlert(t(`${NS}.SALVO`));
    emit('fechar');
  } catch (falha) {
    mostrarRecusa(falha);
  }
};
</script>

<template>
  <AgenteGaveta
    :titulo="t(`${NS}.GAVETA_TITULO`, { nome })"
    @fechar="emit('fechar')"
  >
    <p :id="`${base}-dica`" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.GAVETA_DICA`, { nome }) }}
    </p>
    <DadosDoAtendimento
      ref="campos"
      v-model:endereco="endereco"
      v-model:telefone="telefone"
      :nome="nome"
      :conferir="conferir"
      :bloqueado="salvando"
      :erro-do-telefone="erroDoTelefone"
      :erro-do-endereco="erroDoEndereco"
    />
    <template #rodape>
      <AgenteErro
        v-if="falhou"
        data-erro
        :titulo="tituloDoErro"
        :garantia="t(`${NS}.ERRO_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="salvando"
        @acao="salvar"
      />
      <div class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="salvando"
          @click="emit('fechar')"
        >
          {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
        </AgenteBotao>
        <AgenteBotao
          v-if="!falhou"
          data-salvar
          tamanho="lg"
          :carregando="salvando"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
