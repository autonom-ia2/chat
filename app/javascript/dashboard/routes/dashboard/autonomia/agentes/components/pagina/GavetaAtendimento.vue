<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import DadosDoAtendimento from './DadosDoAtendimento.vue';
import {
  lerAtendimento,
  salvarAtendimento,
} from '../../composables/useDadosDoAtendimento';

// #1479 (opção B do Rodrigo) — "Endereço e telefone de {nome}": gaveta curta do bloco próprio da página, nos dois
// modos (manual e conversando). Só os dois campos, Salvar e Cancelar; o foco fica preso na AgenteGaveta. Telefone
// incompleto não salva: leva ao campo com o aviso. Fechar sem salvar não grava nada.
// PROTÓTIPO: grava pelo adaptador falso (useDadosDoAtendimento), sem backend ainda.
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
const salvando = ref(false);

const salvar = async () => {
  if (salvando.value) return;
  if (campos.value?.incompleto) {
    conferir.value = true;
    campos.value.focarTelefone();
    return;
  }
  falhou.value = false;
  salvando.value = true;
  try {
    await salvarAtendimento(props.agente, {
      endereco: endereco.value,
      telefone: telefone.value,
    });
    useAlert(t(`${NS}.SALVO`));
    emit('fechar');
  } catch {
    falhou.value = true;
  } finally {
    salvando.value = false;
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
    />
    <template #rodape>
      <AgenteErro
        v-if="falhou"
        data-erro
        :titulo="t(`${NS}.ERRO`)"
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
