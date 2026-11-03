<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentesDoPostAPI from 'dashboard/api/agentesDoPost';
import AgenteBotao from '../AgenteBotao.vue';
import MaterialLinha from '../pagina/MaterialLinha.vue';
import {
  ESTADO_MATERIAL,
  estadoDoMaterial,
} from '../../utils/estadoDoMaterial';

// #2487 (PR 3b do #2436) — o material só deste post ou anúncio: o dono anexa um arquivo, e o agente da porta lê só para
// responder os comentários dele (não entra no material do agente nem no atendimento). A linha é a mesma do material do
// agente (Lendo…, Revisando…, Pronto, Precisa de você). Enquanto alguma estiver sendo lida ou revisada, a lista se relê.
// Quem só vê tem a lista, sem anexar nem tirar. `semTexto`: quem chama já explicou (o "Anexar agora" logo depois de ligar).
const props = defineProps({
  careId: { type: Number, required: true },
  podeMudar: { type: Boolean, default: false },
  semTexto: { type: Boolean, default: false },
});

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.SABE.MATERIAL';
const TIPOS = ['pdf', 'docx', 'xlsx', 'txt', 'md', 'json'];
const ACCEPT = TIPOS.map(tipo => `.${tipo}`).join(',');
const RELER_A_CADA_MS = 5000;
const ANDANDO = [ESTADO_MATERIAL.LENDO, ESTADO_MATERIAL.REVISANDO];

const materiais = ref(null);
const enviando = ref(false);
const erro = ref('');
const seletor = ref(null);
let relendo = null;

const andando = computed(() =>
  (materiais.value || []).some(fonte =>
    ANDANDO.includes(estadoDoMaterial(fonte))
  )
);

const parar = () => {
  clearTimeout(relendo);
  relendo = null;
};

// Uma falha no meio da leitura não congela a linha em "Lendo…": relê do mesmo jeito, e o aviso sai quando der certo.
const carregar = async () => {
  parar();
  try {
    const { data } = await AgentesDoPostAPI.materiais(props.careId);
    materiais.value = data.materiais;
    erro.value = '';
  } catch {
    materiais.value = materiais.value || [];
    erro.value = t(`${KEY}.ERRO_LISTA`);
  }
  if (andando.value) relendo = setTimeout(carregar, RELER_A_CADA_MS);
};

const motivoDoErro = error =>
  error?.response?.data?.error === 'no_agent' ? 'SEM_AGENTE' : 'ERRO_ENVIO';

const anexar = async event => {
  const [arquivo] = Array.from(event.target.files || []);
  event.target.value = '';
  if (!arquivo) return;
  enviando.value = true;
  erro.value = '';
  try {
    await AgentesDoPostAPI.anexar(props.careId, arquivo);
    await carregar();
  } catch (error) {
    erro.value = t(`${KEY}.${motivoDoErro(error)}`);
  } finally {
    enviando.value = false;
  }
};

const tirar = async fonte => {
  erro.value = '';
  try {
    await AgentesDoPostAPI.tirar(props.careId, fonte.id);
    materiais.value = materiais.value.filter(item => item.id !== fonte.id);
  } catch {
    erro.value = t(`${KEY}.ERRO_TIRAR`);
  }
};

onMounted(carregar);
onBeforeUnmount(parar);
</script>

<template>
  <div data-material-do-post class="flex flex-col gap-3">
    <p v-if="!semTexto" class="m-0 text-sm leading-6 text-n-slate-11">
      {{ t(`${KEY}.TEXTO`) }}
    </p>
    <ul
      v-if="materiais?.length"
      data-materiais-do-post
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <MaterialLinha
        v-for="fonte in materiais"
        :key="fonte.id"
        :fonte="fonte"
        :nome-agente="fonte.agente"
        :estado="estadoDoMaterial(fonte)"
        :pode-gerenciar="podeMudar"
        :pode-reler="false"
        @tirar="tirar"
        @mandar-outro="seletor?.click()"
      />
    </ul>
    <p v-else-if="materiais" class="m-0 text-sm text-n-slate-11">
      {{ t(`${KEY}.VAZIO`) }}
    </p>
    <p
      v-if="erro"
      data-material-erro
      role="alert"
      class="m-0 text-sm leading-6 text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <div
      v-if="podeMudar"
      class="relative flex flex-wrap items-center gap-x-3 gap-y-1"
    >
      <input
        ref="seletor"
        data-anexar-arquivo
        type="file"
        class="sr-only"
        tabindex="-1"
        :accept="ACCEPT"
        @change="anexar"
      />
      <AgenteBotao
        data-anexar
        variante="contorno"
        icone="i-lucide-paperclip"
        :carregando="enviando"
        :rotulo-carregando="t(`${KEY}.ENVIANDO`)"
        @click="seletor?.click()"
      >
        {{ t(`${KEY}.ANEXAR`) }}
      </AgenteBotao>
      <span class="text-xs text-n-slate-11">{{ t(`${KEY}.TIPOS`) }}</span>
    </div>
  </div>
</template>
