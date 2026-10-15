<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AgenteGaveta from './AgenteGaveta.vue';
import AgenteBotao from './AgenteBotao.vue';
import ChaveDeAcesso from './ChaveDeAcesso.vue';

// #1648 (mockup-2) — conectar e editar um agente de outro sistema (agent_bot do tipo webhook) a
// partir da lista de Agentes. Mesmos campos do formulário de Configurações › Robôs (nome,
// descrição, endereço do webhook, foto) e a chave de acesso, em linguagem simples.
// Sem `agente`: conectar. Ao conectar, a gaveta mostra a chave nova (o único passo que falta).
// Com `agente`: a ficha, com Salvar e Apagar.
const props = defineProps({
  agente: { type: Object, default: null },
});

const emit = defineEmits(['fechar', 'apagar']);

const { t } = useI18n();
const store = useStore();
const editando = computed(() => Boolean(props.agente));
const form = reactive({
  nome: props.agente?.name || '',
  descricao: props.agente?.description || '',
  endereco: props.agente?.outgoing_url || '',
  foto: null,
  fotoUrl: props.agente?.thumbnail || '',
});
const salvando = ref(false);
const chaveNova = ref('');

const titulo = computed(() => {
  if (chaveNova.value) return t('AGENTS.OUTRO_SISTEMA.PRONTO_TITULO');
  return editando.value
    ? props.agente.name
    : t('AGENTS.OUTRO_SISTEMA.CONECTAR');
});

const aoEscolherFoto = ({ file, url }) => {
  form.foto = file;
  form.fotoUrl = url;
};
const aoTirarFoto = () => {
  form.foto = null;
  form.fotoUrl = '';
};

const salvar = async () => {
  if (salvando.value) return;
  salvando.value = true;
  const dados = {
    name: form.nome,
    description: form.descricao,
    outgoing_url: form.endereco,
    bot_type: 'webhook',
    avatar: form.foto,
  };
  try {
    if (editando.value) {
      await store.dispatch('agentBots/update', {
        id: props.agente.id,
        data: dados,
      });
      useAlert(t('AGENTS.OUTRO_SISTEMA.SALVOU'));
      emit('fechar');
      return;
    }
    const criado = await store.dispatch('agentBots/create', dados);
    chaveNova.value = criado?.access_token || '';
    if (!chaveNova.value) emit('fechar');
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <template v-if="chaveNova">
      <p data-pronto class="m-0 text-base text-n-slate-12">
        {{ t('AGENTS.OUTRO_SISTEMA.PRONTO_TEXTO') }}
      </p>
      <ChaveDeAcesso :valor="chaveNova" />
    </template>
    <form
      v-else
      id="form-outro-sistema"
      class="flex flex-col gap-5"
      @submit.prevent="salvar"
    >
      <p v-if="!editando" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.OUTRO_SISTEMA.EXPLICA') }}
      </p>
      <div class="flex flex-col items-start gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.OUTRO_SISTEMA.FOTO') }}
        </span>
        <Avatar
          :src="form.fotoUrl"
          :name="form.nome"
          :size="68"
          allow-upload
          icon-name="i-lucide-bot-message-square"
          @upload="aoEscolherFoto"
          @delete="aoTirarFoto"
        />
      </div>
      <Input
        id="outro-sistema-nome"
        v-model="form.nome"
        :label="t('AGENTS.OUTRO_SISTEMA.NOME')"
        :placeholder="t('AGENTS.OUTRO_SISTEMA.NOME_EXEMPLO')"
      />
      <TextArea
        id="outro-sistema-descricao"
        v-model="form.descricao"
        :label="t('AGENTS.OUTRO_SISTEMA.DESCRICAO')"
        :placeholder="t('AGENTS.OUTRO_SISTEMA.DESCRICAO_EXEMPLO')"
      />
      <Input
        id="outro-sistema-endereco"
        v-model="form.endereco"
        type="url"
        :label="t('AGENTS.OUTRO_SISTEMA.ENDERECO')"
        placeholder="https://"
        :message="t('AGENTS.OUTRO_SISTEMA.ENDERECO_AJUDA')"
      />
      <ChaveDeAcesso
        v-if="editando && agente.access_token"
        :valor="agente.access_token"
      />
    </form>
    <template #rodape>
      <AgenteBotao
        v-if="chaveNova"
        data-concluir
        tamanho="lg"
        bloco
        @click="emit('fechar')"
      >
        {{ t('AGENTS.OUTRO_SISTEMA.CONCLUIR') }}
      </AgenteBotao>
      <template v-else>
        <AgenteBotao
          data-salvar
          type="submit"
          form="form-outro-sistema"
          tamanho="lg"
          bloco
          :carregando="salvando"
          :desabilitado="!form.nome || !form.endereco"
        >
          {{
            editando
              ? t('AGENTS.OUTRO_SISTEMA.SALVAR')
              : t('AGENTS.OUTRO_SISTEMA.BOTAO_CONECTAR')
          }}
        </AgenteBotao>
        <AgenteBotao
          v-if="editando"
          data-apagar
          variante="fantasma"
          icone="i-lucide-trash-2"
          class="!text-n-ruby-11"
          @click="emit('apagar', agente)"
        >
          {{ t('AGENTS.OUTRO_SISTEMA.APAGAR') }}
        </AgenteBotao>
      </template>
    </template>
  </AgenteGaveta>
</template>
