<script setup>
import { computed, onBeforeUnmount, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteAvatar from '../AgenteAvatar.vue';
import { MAX_FOTO, TIPOS_FOTO } from '../../utils/pagina';

// #1181 PR3 (protótipo T12) — Foto e nome. Grava só o que mudou: o nome com {id, name}; a foto pelas
// ações de avatar que já existem (updateAvatar/deleteAvatar). Foto JPG ou PNG de até 5 MB. Vindo do
// "Voltar para {nome antigo}" do Mudar conversando, o campo já chega com o nome antigo.
const props = defineProps({
  agente: { type: Object, required: true },
  nomeSugerido: { type: String, default: '' },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.PAGINA.FOTO';
const base = `foto-${useId()}`;

const nome = ref(props.nomeSugerido || props.agente.name || '');
const arquivo = ref(null);
const previa = ref(props.agente.avatar_url || '');
const erroNome = ref('');
const erroFoto = ref('');
const falhou = ref(false);
const salvando = ref(false);
const seletor = ref(null);
const campoNome = ref(null);

const soltarPrevia = () => {
  if (arquivo.value && previa.value) URL.revokeObjectURL(previa.value);
};

onMounted(() => campoNome.value?.focus());
onBeforeUnmount(soltarPrevia);

const nomeAtual = computed(() => props.agente.name || '');

const aoEscolher = evento => {
  const [escolhido] = evento.target.files || [];
  evento.target.value = '';
  if (!escolhido) return;
  if (!TIPOS_FOTO.includes(escolhido.type) || escolhido.size > MAX_FOTO) {
    erroFoto.value = t(`${NS}.FOTO_ERRO`);
    return;
  }
  erroFoto.value = '';
  soltarPrevia();
  arquivo.value = escolhido;
  previa.value = URL.createObjectURL(escolhido);
};

const tirarFoto = () => {
  soltarPrevia();
  arquivo.value = null;
  previa.value = '';
};

const gravar = async () => {
  const id = props.agente.id;
  const novoNome = nome.value.trim();
  if (novoNome !== nomeAtual.value) {
    await store.dispatch('autonomiaAgents/update', { id, name: novoNome });
  }
  if (arquivo.value) {
    await store.dispatch('autonomiaAgents/updateAvatar', {
      agentId: id,
      avatar: arquivo.value,
    });
  } else if (!previa.value && props.agente.avatar_url) {
    await store.dispatch('autonomiaAgents/deleteAvatar', id);
  }
};

const salvar = async () => {
  if (salvando.value) return;
  if (!nome.value.trim()) {
    erroNome.value = t(`${NS}.NOME_ERRO`);
    campoNome.value?.focus();
    return;
  }
  erroNome.value = '';
  falhou.value = false;
  salvando.value = true;
  try {
    await gravar();
    useAlert(t(`${NS}.PRONTO`));
    emit('fechar');
  } catch {
    falhou.value = true;
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <AgenteGaveta :titulo="t(`${NS}.TITULO`)" @fechar="emit('fechar')">
    <div class="flex flex-col gap-6" :aria-busy="salvando ? 'true' : undefined">
      <AgenteErro
        v-if="falhou"
        data-erro
        :titulo="t(`${NS}.ERRO`)"
        :garantia="t(`${NS}.ERRO_GARANTIA`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="salvando"
        @acao="salvar"
      />
      <div class="flex items-center gap-4">
        <AgenteAvatar
          class="!size-24 !text-3xl"
          :nome="nome || agente.name || '?'"
          :src="previa"
          tom="atendendo"
        />
        <div class="flex flex-col gap-2">
          <AgenteBotao
            data-trocar-foto
            variante="contorno"
            icone="i-lucide-image"
            @click="seletor?.click()"
          >
            {{ t(`${NS}.TROCAR`) }}
          </AgenteBotao>
          <AgenteBotao
            v-if="previa"
            data-tirar-foto
            variante="fantasma"
            icone="i-lucide-trash-2"
            @click="tirarFoto"
          >
            {{ t(`${NS}.TIRAR`) }}
          </AgenteBotao>
          <input
            ref="seletor"
            data-seletor
            type="file"
            accept="image/png,image/jpeg"
            class="hidden"
            @change="aoEscolher"
          />
        </div>
      </div>
      <p
        v-if="erroFoto"
        role="alert"
        data-erro-foto
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ erroFoto }}
      </p>
      <div class="flex flex-col gap-1">
        <label
          :for="`${base}-nome`"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.NOME`) }}
        </label>
        <input
          :id="`${base}-nome`"
          ref="campoNome"
          v-model="nome"
          data-nome
          maxlength="40"
          autocomplete="off"
          :aria-invalid="erroNome ? 'true' : undefined"
          :aria-describedby="erroNome ? `${base}-erro` : undefined"
          class="px-3 text-base rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12"
        />
        <p
          v-if="erroNome"
          :id="`${base}-erro`"
          data-erro-nome
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ erroNome }}
        </p>
      </div>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.NOTA`, { nome: agente.name }) }}
      </p>
    </div>
    <template #rodape>
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
