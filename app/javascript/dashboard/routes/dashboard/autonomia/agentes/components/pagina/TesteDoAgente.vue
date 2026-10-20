<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CelularConversa from '../CelularConversa.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import RespostasRapidas from '../RespostasRapidas.vue';
import CompositorAA from '../CompositorAA.vue';
import AprenderComArquivo from './AprenderComArquivo.vue';
import { AVISO_TESTE } from '../../composables/useTesteDoAgente';

// #1181 PR3 (protótipo testPhone, T08 e a coluna de T11) — o celular de teste: perguntas prontas do
// modelo, campo para escrever, "Limpar teste", o aviso de que o agente passaria para a equipe e, para
// quem pode mudar, "Respondeu errado? Mudar conversando". Os erros seguem o padrão único (T17).
// `teste` é o retorno do useTesteDoAgente de quem usa (a mesma conversa entre gaveta e página).
// O cabeçalho do celular tem o nome da conta, como o cliente vê; "Atendido por {nome}" embaixo.
// #1427 — o clipe (só no Testar da página, na Fase 2): `clipe` 'fotos' (quem só vê) ou 'tudo' (quem gerencia); vazio = sem
// clipe, o campo de antes. A foto vai com a pergunta e é lida só neste teste; outro arquivo não é lido: vira a pergunta
// "Quer que {nome} aprenda com isto?" (AprenderComArquivo), um por vez.
const props = defineProps({
  teste: { type: Object, required: true },
  nome: { type: String, required: true },
  tipo: { type: String, default: 'support' },
  podeMudar: { type: Boolean, default: false },
  clipe: {
    type: String,
    default: '',
    validator: v => ['', 'fotos', 'tudo'].includes(v),
  },
  agenteId: { type: Number, default: 0 },
});

const emit = defineEmits(['errado', 'verSabe']);

const { t } = useI18n();
const campoId = `teste-${useId()}`;
const campo = ref(null);
const compositor = ref(null);
const texto = ref('');
const paraAprender = ref([]);
const conta = useMapGetter('getCurrentAccount');
const nomeNoCelular = computed(() => conta.value?.name || props.nome);

// As perguntas prontas de cada tipo, com as chaves escritas por inteiro (o gate do i18n não aceita chave montada).
const perguntasProntas = computed(() => {
  if (props.tipo === 'sdr') {
    return [
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SDR.A'),
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SDR.B'),
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SDR.C'),
    ];
  }
  if (props.tipo === 'reception') {
    return [
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.A'),
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.B'),
      t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.C'),
    ];
  }
  return [
    t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.A'),
    t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.B'),
    t('AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.C'),
  ];
});

const mensagens = computed(() => props.teste.mensagens.value);
const digitando = computed(() => props.teste.digitando.value);
const aviso = computed(() => props.teste.aviso.value);
const ultima = computed(() => props.teste.ultima.value);

// #1427 — foto recusada (no navegador ou no servidor): o que a pessoa escreveu volta ao campo, para mandar com outra foto.
watch(aviso, novo => {
  if (novo?.tipo === AVISO_TESTE.FOTO_RECUSADA && novo.texto && !texto.value) {
    texto.value = novo.texto;
  }
});

const focar = () =>
  props.clipe ? compositor.value?.focar() : campo.value?.focus();

const enviar = async () => {
  const pergunta = texto.value.trim();
  if (!pergunta || digitando.value) return;
  texto.value = '';
  await props.teste.enviar(pergunta);
};

const perguntar = pergunta => {
  props.teste.enviar(pergunta);
  focar();
};

// Com o clipe: as fotos vão com a pergunta; os outros arquivos esperam a resposta de "Quer que aprenda".
const ehImagem = arquivo => (arquivo.type || '').startsWith('image/');
const enviarComClipe = async ({ texto: escrito, anexos }) => {
  if (digitando.value) return;
  const fotos = anexos.filter(ehImagem);
  const outros = anexos.filter(arquivo => !ehImagem(arquivo));
  texto.value = '';
  if (outros.length) paraAprender.value = [...paraAprender.value, ...outros];
  if (escrito || fotos.length) await props.teste.enviar(escrito, fotos);
};

const resolvido = arquivo => {
  paraAprender.value = paraAprender.value.filter(item => item !== arquivo);
};

const aoTeclar = evento => {
  if (evento.key !== 'Enter' || evento.shiftKey || evento.isComposing) return;
  evento.preventDefault();
  enviar();
};

const limpar = () => {
  props.teste.limpar();
  paraAprender.value = [];
  focar();
};
defineExpose({ focar });
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="mensagens.length || teste.atualizado.value"
      class="flex items-center justify-end"
    >
      <AgenteBotao
        data-limpar
        variante="fantasma"
        :inativo="digitando"
        @click="limpar"
      >
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.LIMPAR') }}
      </AgenteBotao>
    </div>
    <p
      v-if="teste.atualizado.value"
      data-atualizado
      class="flex items-center gap-2 m-0 text-sm font-medium text-n-teal-11"
    >
      <span class="i-lucide-circle-check size-4" aria-hidden="true" />
      {{ t('AGENTS.JORNADA.PAGINA.TESTE.ATUALIZADO') }}
    </p>
    <CelularConversa
      :mensagens="mensagens"
      :digitando="digitando"
      :nome="nomeNoCelular"
      :estado="
        digitando
          ? t('AGENTS.JORNADA.PAGINA.TESTE.ESCREVENDO', { nome })
          : t('AGENTS.JORNADA.PAGINA.TESTE.ATENDIDO', { nome })
      "
    />
    <p
      v-if="!mensagens.length && !teste.atualizado.value"
      data-vazio
      class="m-0 text-sm text-center text-n-slate-11"
    >
      {{ t('AGENTS.JORNADA.PAGINA.TESTE.VAZIO') }}
    </p>

    <AgenteErro
      v-if="aviso?.tipo === AVISO_TESTE.FALHA"
      data-aviso="falha"
      :titulo="t('AGENTS.JORNADA.PAGINA.TESTE.FALHOU', { nome })"
      :garantia="t('AGENTS.JORNADA.PAGINA.TESTE.FALHOU_GARANTIA')"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="teste.tentarDeNovo()"
    />
    <AgenteErro
      v-else-if="aviso?.tipo === AVISO_TESTE.DEMORA"
      data-aviso="demora"
      tom="ambar"
      :titulo="t('AGENTS.JORNADA.PAGINA.TESTE.DEMORA')"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="teste.tentarDeNovo()"
    />
    <AgenteErro
      v-else-if="aviso?.tipo === AVISO_TESTE.OFFLINE"
      data-aviso="offline"
      tom="ambar"
      :titulo="t('AGENTS.JORNADA.ERRO.OFFLINE')"
      :garantia="t('AGENTS.JORNADA.ERRO.OFFLINE_GARANTIA')"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="teste.tentarDeNovo()"
    />
    <AgenteErro
      v-else-if="aviso?.tipo === AVISO_TESTE.INCOMPLETO"
      data-aviso="incompleto"
      tom="ambar"
      :titulo="t('AGENTS.JORNADA.PAGINA.TESTE.INCOMPLETO', { nome })"
    />
    <AgenteErro
      v-else-if="aviso?.tipo === AVISO_TESTE.FOTO_RECUSADA"
      data-aviso="foto-recusada"
      tom="ambar"
      :titulo="
        aviso.grande
          ? t('AGENTS.JORNADA.PAGINA.SABE.FOTO_GRANDE')
          : aviso.mensagem
      "
    />

    <template v-if="ultima">
      <p
        v-if="ultima.passaria"
        data-passaria
        class="flex items-center gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
      >
        <span class="i-lucide-users size-4 shrink-0" aria-hidden="true" />
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.PASSARIA', { nome }) }}
      </p>
      <button
        v-if="podeMudar"
        data-errado
        type="button"
        class="self-start text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('errado', ultima)"
      >
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.ERRADO') }}
      </button>
    </template>

    <RespostasRapidas
      :opcoes="perguntasProntas"
      :rotulo="t('AGENTS.JORNADA.PAGINA.TESTE.PERGUNTAS')"
      :desabilitado="digitando"
      @escolher="perguntar"
    />
    <AprenderComArquivo
      v-if="clipe === 'tudo' && agenteId"
      :arquivos="paraAprender"
      :agente-id="agenteId"
      :nome="nome"
      @resolvido="resolvido"
      @ver-sabe="emit('verSabe')"
    />
    <CompositorAA
      v-if="clipe"
      ref="compositor"
      v-model="texto"
      anexar
      :so-imagens="clipe === 'fotos'"
      :rotulo-anexar="
        clipe === 'tudo' ? t('AGENTS.JORNADA.PAGINA.TESTE.ANEXAR') : ''
      "
      :placeholder="t('AGENTS.JORNADA.PAGINA.TESTE.ESCREVA')"
      :enviando="digitando"
      @enviar="enviarComClipe"
    />
    <form v-else class="relative flex items-end gap-2" @submit.prevent="enviar">
      <label :for="campoId" class="sr-only">{{
        t('AGENTS.JORNADA.PAGINA.TESTE.ESCREVA')
      }}</label>
      <textarea
        :id="campoId"
        ref="campo"
        v-model="texto"
        rows="1"
        :placeholder="t('AGENTS.JORNADA.PAGINA.TESTE.ESCREVA')"
        class="flex-1 min-w-0 px-3 py-2.5 text-base bg-n-solid-1 rounded-xl ring-1 ring-inset ring-n-slate-7 border-0 outline-none resize-none !mb-0 min-h-11 max-h-32 text-n-slate-12 placeholder:text-n-slate-10 focus-visible:ring-2 focus-visible:ring-n-blue-11"
        @keydown="aoTeclar"
      />
      <AgenteBotao
        type="submit"
        data-enviar
        :inativo="digitando || !texto.trim()"
      >
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.ENVIAR') }}
      </AgenteBotao>
    </form>
  </div>
</template>
