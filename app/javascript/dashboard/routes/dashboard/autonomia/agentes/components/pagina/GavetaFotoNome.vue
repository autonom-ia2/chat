<script setup>
import { computed, onBeforeUnmount, onMounted, ref, useId } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteAvatar from '../AgenteAvatar.vue';
import { MAX_FOTO, TIPOS_FOTO } from '../../utils/pagina';
import { usaFotoDoCanal } from '../../utils/fotoDoCanal';

// #1181 PR3 (protótipo T12) — Foto e nome. Grava só o que mudou: o nome com {id, name}; a foto pelas
// ações de avatar que já existem (updateAvatar/deleteAvatar). Foto JPG ou PNG de até 5 MB. Vindo do
// "Voltar para {nome antigo}" do Mudar conversando, o campo já chega com o nome antigo.
// Agente externo: o cliente vê a foto do canal, então a gaveta vira só "Nome" — mostra a foto do
// canal sem poder trocar e grava só o nome. `canal`: { nome, foto } da caixa que dá a foto, ou null;
// `temCanal`: o agente responde em alguma caixa (mesmo sem a leitura do nome dela).
const props = defineProps({
  agente: { type: Object, required: true },
  nomeSugerido: { type: String, default: '' },
  canal: { type: Object, default: null },
  temCanal: { type: Boolean, default: false },
  // Quem pode abrir Mudar conversando (gerencia, e o agente não é manual nem cotação): a frase da
  // nota leva até lá. Sem isso, "Mudar conversando" fica só em negrito.
  podeMudar: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'mudar']);

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
const externo = computed(() => usaFotoDoCanal(props.agente));
const fotoExibida = computed(() =>
  externo.value
    ? props.canal?.foto || props.agente.avatar_url || ''
    : previa.value
);
const fraseDaFoto = computed(() => {
  // Canal sem foto guardada (caso comum do WhatsApp, #1281): dizer como pôr a foto, e não
  // afirmar que a imagem ao lado é a do canal.
  if (props.canal?.nome && !props.canal?.foto) {
    return t(`${NS}.FOTO_CANAL_SEM_FOTO`, { canal: props.canal.nome });
  }
  if (props.canal?.nome) {
    return t(`${NS}.FOTO_DO_CANAL`, { canal: props.canal.nome });
  }
  if (props.temCanal) return t(`${NS}.FOTO_DO_CANAL_GERAL`);
  return t(`${NS}.FOTO_SEM_CANAL`, { nome: nomeAtual.value });
});

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
  if (externo.value) return;
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
  <AgenteGaveta
    :titulo="externo ? t(`${NS}.TITULO_NOME`) : t(`${NS}.TITULO`)"
    @fechar="emit('fechar')"
  >
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
          :src="fotoExibida"
          tom="atendendo"
        />
        <p
          v-if="externo"
          data-foto-do-canal
          class="m-0 text-base text-n-slate-12"
        >
          {{ fraseDaFoto }}
        </p>
        <div v-else class="flex flex-col gap-2">
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
      <I18nT
        data-nota
        :keypath="`${NS}.NOTA`"
        tag="p"
        scope="global"
        class="m-0 text-sm text-n-slate-11"
      >
        <template #acao>
          <!-- `inline` + py-3: a área de toque cresce para 44 px sem empurrar as linhas do texto. -->
          <button
            v-if="podeMudar"
            data-ir-mudar
            type="button"
            class="inline py-3 font-semibold rounded text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="emit('mudar')"
          >
            {{ t(`${NS}.NOTA_ACAO`) }}
          </button>
          <b v-else data-acao-texto class="font-semibold text-n-slate-12">{{
            t(`${NS}.NOTA_ACAO`)
          }}</b>
        </template>
      </I18nT>
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
