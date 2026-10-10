<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CelularConversa from '../CelularConversa.vue';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import RespostasRapidas from '../RespostasRapidas.vue';
import { AVISO_TESTE } from '../../composables/useTesteDoAgente';

// #1181 PR3 (protótipo testPhone, T08 e a coluna de T11) — o celular de teste: perguntas prontas do
// modelo, campo para escrever, "Limpar teste", o aviso de que o agente passaria para a equipe e, para
// quem pode mudar, "Respondeu errado? Mudar conversando". Os erros seguem o padrão único (T17).
// `teste` é o retorno do useTesteDoAgente de quem usa (a mesma conversa entre gaveta e página).
// O cabeçalho do celular tem o nome da conta, como o cliente vê; "Atendido por {nome}" embaixo.
const props = defineProps({
  teste: { type: Object, required: true },
  nome: { type: String, required: true },
  tipo: { type: String, default: 'support' },
  podeMudar: { type: Boolean, default: false },
});

const emit = defineEmits(['errado']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.TESTE';
const campoId = `teste-${useId()}`;
const campo = ref(null);
const texto = ref('');
const conta = useMapGetter('getCurrentAccount');
const nomeNoCelular = computed(() => conta.value?.name || props.nome);

const CHIPS_POR_TIPO = { sdr: 'SDR', reception: 'RECEPTION' };
const perguntasProntas = computed(() => {
  const chave = CHIPS_POR_TIPO[props.tipo] || 'SUPPORT';
  return ['A', 'B', 'C'].map(letra => t(`${NS}.CHIPS.${chave}.${letra}`));
});

const mensagens = computed(() => props.teste.mensagens.value);
const digitando = computed(() => props.teste.digitando.value);
const aviso = computed(() => props.teste.aviso.value);
const ultima = computed(() => props.teste.ultima.value);

const enviar = async () => {
  const pergunta = texto.value.trim();
  if (!pergunta || digitando.value) return;
  texto.value = '';
  await props.teste.enviar(pergunta);
};

const perguntar = pergunta => {
  props.teste.enviar(pergunta);
  campo.value?.focus();
};

const aoTeclar = evento => {
  if (evento.key !== 'Enter' || evento.shiftKey || evento.isComposing) return;
  evento.preventDefault();
  enviar();
};

const limpar = () => {
  props.teste.limpar();
  campo.value?.focus();
};

const focar = () => campo.value?.focus();
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
        {{ t(`${NS}.LIMPAR`) }}
      </AgenteBotao>
    </div>
    <p
      v-if="teste.atualizado.value"
      data-atualizado
      class="flex items-center gap-2 m-0 text-sm font-medium text-n-teal-11"
    >
      <span class="i-lucide-circle-check size-4" aria-hidden="true" />
      {{ t(`${NS}.ATUALIZADO`) }}
    </p>
    <CelularConversa
      :mensagens="mensagens"
      :digitando="digitando"
      :nome="nomeNoCelular"
      :estado="
        digitando
          ? t(`${NS}.ESCREVENDO`, { nome })
          : t(`${NS}.ATENDIDO`, { nome })
      "
    />
    <p
      v-if="!mensagens.length && !teste.atualizado.value"
      data-vazio
      class="m-0 text-sm text-center text-n-slate-11"
    >
      {{ t(`${NS}.VAZIO`) }}
    </p>

    <AgenteErro
      v-if="aviso?.tipo === AVISO_TESTE.FALHA"
      data-aviso="falha"
      :titulo="t(`${NS}.FALHOU`, { nome })"
      :garantia="t(`${NS}.FALHOU_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="teste.tentarDeNovo()"
    />
    <AgenteErro
      v-else-if="aviso?.tipo === AVISO_TESTE.DEMORA"
      data-aviso="demora"
      tom="ambar"
      :titulo="t(`${NS}.DEMORA`)"
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
      :titulo="t(`${NS}.INCOMPLETO`, { nome })"
    />

    <template v-if="ultima">
      <p
        v-if="ultima.passaria"
        data-passaria
        class="flex items-center gap-2 p-3 m-0 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
      >
        <span class="i-lucide-users size-4 shrink-0" aria-hidden="true" />
        {{ t(`${NS}.PASSARIA`, { nome }) }}
      </p>
      <button
        v-if="podeMudar"
        data-errado
        type="button"
        class="self-start text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('errado', ultima)"
      >
        {{ t(`${NS}.ERRADO`) }}
      </button>
    </template>

    <RespostasRapidas
      :opcoes="perguntasProntas"
      :rotulo="t(`${NS}.PERGUNTAS`)"
      :desabilitado="digitando"
      @escolher="perguntar"
    />
    <form class="flex items-end gap-2" @submit.prevent="enviar">
      <label :for="campoId" class="sr-only">{{ t(`${NS}.ESCREVA`) }}</label>
      <textarea
        :id="campoId"
        ref="campo"
        v-model="texto"
        rows="1"
        :placeholder="t(`${NS}.ESCREVA`)"
        class="flex-1 min-w-0 px-3 py-2.5 text-base bg-n-solid-1 rounded-xl ring-1 ring-inset ring-n-slate-7 border-0 outline-none resize-none !mb-0 min-h-11 max-h-32 text-n-slate-12 placeholder:text-n-slate-10 focus-visible:ring-2 focus-visible:ring-n-blue-11"
        @keydown="aoTeclar"
      />
      <AgenteBotao
        type="submit"
        data-enviar
        :inativo="digitando || !texto.trim()"
      >
        {{ t(`${NS}.ENVIAR`) }}
      </AgenteBotao>
    </form>
  </div>
</template>
