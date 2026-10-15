<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AgenteGaveta from './AgenteGaveta.vue';
import AgenteBotao from './AgenteBotao.vue';
import FotoDoAgente from './FotoDoAgente.vue';

// #1648 (mockup-2) — "Alterar" de uma seção da página do agente de outro sistema, no padrão das
// nossas seções: gaveta com o campo e, no rodapé, Cancelar e Salvar.
// campo: 'faz' (O que ele faz) · 'conexao' (endereço do webhook) · 'nome-foto' (menu "⋯").
const props = defineProps({
  agente: { type: Object, required: true },
  campo: {
    type: String,
    required: true,
    validator: v => ['faz', 'conexao', 'nome-foto'].includes(v),
  },
});

const emit = defineEmits(['fechar']);

const NS = 'AGENTS.OUTRO_SISTEMA';
const { t } = useI18n();
const store = useStore();
const salvando = ref(false);
const form = reactive({
  nome: props.agente.name || '',
  descricao: props.agente.description || '',
  endereco: props.agente.outgoing_url || '',
  foto: null,
  fotoUrl: props.agente.thumbnail || '',
});

const TITULOS = {
  faz: 'PAGINA.TITULO_FAZ',
  conexao: 'PAGINA.TITULO_CONEXAO',
  'nome-foto': 'PAGINA.TITULO_NOME_FOTO',
};
const titulo = computed(() =>
  t(`${NS}.${TITULOS[props.campo]}`, { nome: props.agente.name })
);

const aoEscolherFoto = ({ file, url }) => {
  form.foto = file;
  form.fotoUrl = url;
};

const DADOS = {
  faz: () => ({ description: form.descricao }),
  conexao: () => ({ outgoing_url: form.endereco }),
  'nome-foto': () => ({ name: form.nome, avatar: form.foto }),
};

const salvar = async () => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    await store.dispatch('agentBots/update', {
      id: props.agente.id,
      data: DADOS[props.campo](),
    });
    useAlert(t(`${NS}.SALVOU`));
    emit('fechar');
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <form
      id="form-alterar-outro"
      class="flex flex-col gap-5"
      @submit.prevent="salvar"
    >
      <TextArea
        v-if="campo === 'faz'"
        id="outro-descricao"
        v-model="form.descricao"
        :label="t(`${NS}.DESCRICAO`)"
        :placeholder="t(`${NS}.DESCRICAO_EXEMPLO`)"
      />
      <Input
        v-else-if="campo === 'conexao'"
        id="outro-endereco"
        v-model="form.endereco"
        type="url"
        :label="t(`${NS}.ENDERECO`)"
        placeholder="https://"
        :message="t(`${NS}.ENDERECO_AJUDA`)"
      />
      <template v-else>
        <FotoDoAgente
          :nome="form.nome"
          :src="form.fotoUrl"
          @escolher="aoEscolherFoto"
        />
        <Input
          id="outro-nome"
          v-model="form.nome"
          :label="t(`${NS}.NOME`)"
          :placeholder="t(`${NS}.NOME_EXEMPLO`)"
        />
      </template>
    </form>
    <template #rodape>
      <div class="flex flex-wrap justify-end gap-2">
        <AgenteBotao
          variante="contorno"
          tamanho="lg"
          :desabilitado="salvando"
          @click="emit('fechar')"
        >
          {{ t(`${NS}.PAGINA.CANCELAR`) }}
        </AgenteBotao>
        <AgenteBotao
          data-salvar
          type="submit"
          form="form-alterar-outro"
          tamanho="lg"
          :carregando="salvando"
        >
          {{ t(`${NS}.SALVAR`) }}
        </AgenteBotao>
      </div>
    </template>
  </AgenteGaveta>
</template>
