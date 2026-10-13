<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { SINAIS, SINAIS_DE_ALERTA, objetivoPorChave } from '../constants';
import { usavelEmCampanha } from '../helpers/paraMeta';
import { haQuantoTempo, numero } from '../helpers/datas';
import ModeloSelo from './ModeloSelo.vue';
import { useRotuloDoCampo } from '../helpers/campos';
import { previaCurta } from '../helpers/conteudo';

// Um modelo na lista: nome pelo objetivo, o próprio texto (com os campos como
// etiqueta), a situação e a próxima ação.
const props = defineProps({
  modelo: { type: Object, required: true },
  nomesDosNumeros: { type: Array, default: () => [] },
  // Nome da conta do WhatsApp, quando a empresa tem mais de uma.
  nomeDaConta: { type: String, default: '' },
  podeCriar: { type: Boolean, default: false },
  // Quem não cria campanha não vê "Usar em uma campanha".
  podeUsar: { type: Boolean, default: true },
});

const emit = defineEmits(['abrir', 'corrigir', 'usar']);

// Separador visual entre as partes da linha (não é texto para traduzir).
const PONTO = '·';

const { t, locale } = useI18n();
const rotulo = useRotuloDoCampo();
// O começo do texto, cortado entre palavras (nunca no meio de um campo).
const RETICENCIAS = '…';
const previa = computed(() => previaCurta(props.modelo.conteudo.texto, rotulo));

// Formato diferente da mensagem comum ganha uma etiqueta ("Carrossel").
const formato = computed(() => {
  const chave = props.modelo.conteudo.formato;
  return chave && chave !== 'padrao' ? chave : '';
});

const visual = computed(() => objetivoPorChave(props.modelo.objetivo));

const frase = computed(() => {
  const { situacao, enviosNoMes, enviadoEm, pausa, recusa } = props.modelo;
  const base = 'MODELOS_WHATSAPP.LISTA.FRASE';
  if (situacao === 'pronto' && enviosNoMes != null) {
    return t(
      `${base}.PRONTO`,
      { n: numero(enviosNoMes, locale.value) },
      enviosNoMes
    );
  }
  if (situacao === 'pronto')
    return t('MODELOS_WHATSAPP.SITUACOES.pronto.ROTULO');
  // A Meta não diz quando o modelo foi enviado nem desde quando está pausado.
  if (situacao === 'em_analise') {
    return enviadoEm
      ? t(`${base}.EM_ANALISE`, {
          quando: haQuantoTempo(enviadoEm, locale.value),
        })
      : t(`${base}.EM_ANALISE_SEM_DATA`);
  }
  if (situacao === 'desativado') return t(`${base}.DESATIVADO`);
  if (situacao === 'limite') return t(`${base}.LIMITE`);
  if (situacao === 'pausado') {
    return pausa?.desde
      ? t(`${base}.PAUSADO`, {
          quando: haQuantoTempo(pausa.desde, locale.value),
        })
      : t(`${base}.PAUSADO_SEM_DATA`);
  }
  return t(`MODELOS_WHATSAPP.RECUSAS.${recusa?.codigo || 'outro'}.TITULO`);
});

// Saúde (#1338): o selo só aparece quando pede ação; a resposta, quando já saiu.
const sinal = computed(() =>
  props.modelo.situacao === 'pronto' &&
  SINAIS_DE_ALERTA.includes(props.modelo.sinal)
    ? props.modelo.sinal
    : ''
);
const respostas = computed(() => {
  const saude = props.modelo.saude;
  if (props.modelo.situacao !== 'pronto' || !saude?.entregues) return '';
  return t('MODELOS_WHATSAPP.SAUDE.LISTA.RESPONDERAM', {
    n: Math.round((saude.responderam / saude.entregues) * 100),
  });
});

const numeros = computed(() => {
  const [primeiro, ...outros] = props.nomesDosNumeros;
  if (!primeiro) return '';
  return outros.length
    ? t(
        'MODELOS_WHATSAPP.LISTA.NUMEROS_E_MAIS',
        { nome: primeiro, n: outros.length },
        outros.length
      )
    : primeiro;
});

const acao = computed(() => {
  if (props.modelo.situacao === 'recusado' && props.podeCriar)
    return 'corrigir';
  if (
    props.modelo.situacao === 'pronto' &&
    props.podeUsar &&
    usavelEmCampanha(props.modelo)
  )
    return 'usar';
  return '';
});
</script>

<template>
  <li
    :data-modelo="modelo.id"
    class="flex flex-col gap-4 p-5 transition border shadow-sm sm:flex-row sm:items-center rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-blue-6"
    :class="modelo.situacao === 'recusado' ? 'border-n-ruby-6' : ''"
  >
    <button
      type="button"
      class="flex items-start flex-1 min-w-0 gap-4 text-start rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('abrir')"
    >
      <span
        class="hidden sm:grid place-items-center size-12 shrink-0 rounded-2xl"
        :class="visual.tom"
      >
        <span class="size-6" :class="visual.icone" aria-hidden="true" />
      </span>
      <span class="flex flex-col min-w-0 gap-1.5">
        <span class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
          <span class="text-lg font-semibold break-words text-n-slate-12">
            {{ modelo.nome }}
          </span>
          <ModeloSelo :situacao="modelo.situacao" />
          <span
            v-if="sinal"
            :data-selo-sinal="sinal"
            class="inline-flex items-center gap-1.5 px-2.5 py-1 text-sm font-medium rounded-full whitespace-nowrap"
            :class="SINAIS[sinal].selo"
          >
            <span
              class="size-4"
              :class="SINAIS[sinal].icone"
              aria-hidden="true"
            />
            {{ $t(`MODELOS_WHATSAPP.SAUDE.SINAIS.${sinal}.SELO`) }}
          </span>
          <span
            v-if="modelo.sistema"
            data-selo-sistema
            class="inline-flex items-center gap-1 px-2.5 py-1 text-sm font-medium rounded-full bg-n-iris-3 text-n-iris-11"
          >
            <span class="i-lucide-cog size-4" aria-hidden="true" />
            {{ $t('MODELOS_WHATSAPP.SISTEMA.SELO') }}
          </span>
        </span>
        <!-- A conta sempre na própria linha: as colunas não mudam de lugar entre os cartões. -->
        <span v-if="nomeDaConta" data-conta class="text-sm text-n-slate-10">
          {{ $t('MODELOS_WHATSAPP.LISTA.CONTA', { nome: nomeDaConta }) }}
        </span>
        <span class="text-[0.9375rem] leading-relaxed text-n-slate-11">
          <span v-if="!modelo.conteudo.texto.length">
            {{ $t('MODELOS_WHATSAPP.FORMATOS.codigo.TEXTO_FIXO') }}
          </span>
          <template v-for="(pedaco, indice) in previa.pedacos" :key="indice">
            <span
              v-if="pedaco.t === 'campo'"
              class="px-0.5 text-sm font-medium rounded bg-n-blue-2 text-n-blue-11"
            >
              <span>{{ rotulo(pedaco.v) }}</span>
            </span>
            <span v-else>{{ pedaco.v }}</span>
          </template>
          <span v-if="previa.cortado" aria-hidden="true">{{
            RETICENCIAS
          }}</span>
        </span>
        <span
          class="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm"
          :class="
            modelo.situacao === 'recusado'
              ? 'text-n-ruby-11 font-medium'
              : 'text-n-slate-10'
          "
        >
          <span
            v-if="formato"
            class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-slate-3 text-n-slate-11"
          >
            {{ $t(`MODELOS_WHATSAPP.FORMATOS.${formato}.TITULO`) }}
          </span>
          <span>{{ frase }}</span>
          <span v-if="respostas" aria-hidden="true">{{ PONTO }}</span>
          <span v-if="respostas" data-respostas>{{ respostas }}</span>
          <span v-if="numeros" aria-hidden="true">{{ PONTO }}</span>
          <span v-if="numeros" class="text-n-slate-10 font-normal">{{
            numeros
          }}</span>
        </span>
      </span>
    </button>
    <!-- Coluna de largura fixa: o texto e o botão ficam no mesmo lugar em todas as linhas. -->
    <div
      class="shrink-0 sm:flex sm:w-56 sm:justify-end"
      :class="acao ? 'flex' : 'hidden'"
    >
      <Button
        v-if="acao === 'corrigir'"
        data-corrigir
        :label="$t('MODELOS_WHATSAPP.ACOES.CORRIGIR')"
        icon="i-lucide-wrench"
        color="ruby"
        class="min-h-11"
        @click="emit('corrigir')"
      />
      <Button
        v-else-if="acao === 'usar'"
        data-usar
        :label="$t('MODELOS_WHATSAPP.ACOES.USAR')"
        icon="i-lucide-send"
        variant="faded"
        class="min-h-11"
        @click="emit('usar')"
      />
    </div>
  </li>
</template>
