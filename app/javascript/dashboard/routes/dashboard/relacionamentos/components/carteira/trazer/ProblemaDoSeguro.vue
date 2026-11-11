<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CampoDeTelefone from 'dashboard/components-next/conversa-canal/mais/CampoDeTelefone.vue';
import CampoDoSeguro from '../CampoDoSeguro.vue';
import { ACEITA_APOLICES } from '../../../carteira/arquivosDeApolice';
import {
  doCampoDeData,
  formatarValor,
} from '../../../carteira/formatosDoSeguro';
import { useIdioma } from '../../../ficha/idioma';
import { soDigitos } from '../../../fonte/texto';
import { SITUACAO_DO_PROBLEMA } from '../../../trazer/contagem';

// #2897 — um seguro que precisa da pessoa antes de entrar: o problema em
// palavras simples e o conserto ali mesmo (quando termina, qual seguradora,
// qual das duas linhas fica, o telefone, outra foto). Salvar fica sempre
// ligado: sem o dado, o clique diz o que falta, marca o campo e leva o foco.
const props = defineProps({
  problema: { type: Object, required: true },
  seguradoras: { type: Array, default: () => [] },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.PRECISAM.${chave}`, valores);
const idioma = useIdioma();
const id = useId();
const idDoCampo = `${id}-campo`;
const idDaFalta = `${id}-falta`;

// O que a pessoa preenche em cada tipo ('' = escolhe, não escreve).
const CAMPO_DO_TIPO = {
  falta_termina: 'TERMINA',
  seguradora: 'SEGURADORA',
  telefone: 'TELEFONE',
};
const campo = computed(() => CAMPO_DO_TIPO[props.problema.tipo] ?? '');
const doPdf = computed(() => Boolean(props.problema.arquivo));
const aberto = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.ABERTO
);
const guardado = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.GUARDADO
);

// O telefone que veio errado já aparece no campo; só vale depois de consertado.
const telefoneDeInicio =
  props.problema.tipo === 'telefone' && props.problema.valor
    ? `+${soDigitos(props.problema.valor)}`
    : '';
const valor = ref(telefoneDeInicio);
const falta = ref('');
const formulario = ref(null);
const seletorDeArquivo = ref(null);

const PRONTO_PARA_SALVAR = {
  TERMINA: () => doCampoDeData(valor.value) !== null,
  SEGURADORA: () => Boolean(valor.value),
  TELEFONE: () => Boolean(valor.value) && valor.value !== telefoneDeInicio,
};
const paraGuardar = () =>
  campo.value === 'TERMINA' ? doCampoDeData(valor.value) : valor.value;

const focarOCampo = () => {
  const alvo =
    document.getElementById(idDoCampo) ??
    formulario.value?.querySelector('input');
  alvo?.focus();
};

const salvar = () => {
  if (props.ocupado) return;
  if (!PRONTO_PARA_SALVAR[campo.value]()) {
    falta.value = tp(`FALTA.${campo.value}`);
    focarOCampo();
    return;
  }
  emit('guardar', props.problema.linha, paraGuardar());
};

watch(valor, () => {
  falta.value = '';
});

const opcoesDeSeguradora = computed(() =>
  props.seguradoras.map(nome => ({ value: nome, label: nome }))
);

// A frase muda quando o seguro veio de um PDF ("não achei… neste PDF").
const CHAVE_DO_TIPO = {
  falta_termina: ['FALTA_TERMINA', 'FALTA_TERMINA_PDF'],
  seguradora: ['SEGURADORA', 'SEGURADORA'],
  duplicado: ['DUPLICADO', 'DUPLICADO'],
  telefone: ['TELEFONE', 'TELEFONE_PDF'],
  foto_escura: ['FOTO_ESCURA', 'FOTO_ESCURA'],
};
const texto = computed(() => {
  const [daPlanilha, doArquivo] = CHAVE_DO_TIPO[props.problema.tipo];
  return tp(`PROBLEMA.${doPdf.value ? doArquivo : daPlanilha}`, props.problema);
});
const deOnde = computed(() => {
  if (props.problema.tipo === 'foto_escura') return '';
  if (doPdf.value) return tp('ARQUIVO', props.problema);
  return tp(props.problema.outraLinha ? 'LINHAS' : 'LINHA', props.problema);
});
const naPlanilha = dinheiro =>
  tp('NA_PLANILHA', { valor: formatarValor(dinheiro, idioma.value) });

const trocarOArquivo = evento => {
  const [arquivo] = evento.target.files ?? [];
  if (arquivo) emit('guardar', props.problema.linha, arquivo.name);
};
</script>

<template>
  <li
    :data-linha="problema.linha"
    :data-problema="problema.tipo"
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <form
      v-if="aberto"
      ref="formulario"
      class="flex flex-col gap-4"
      novalidate
      @submit.prevent="salvar"
    >
      <div class="flex flex-col gap-1">
        <p class="m-0 text-lg font-semibold text-n-slate-12">{{ texto }}</p>
        <p v-if="deOnde" class="m-0 text-sm text-n-slate-11">{{ deOnde }}</p>
      </div>

      <CampoDoSeguro
        v-if="campo === 'TERMINA'"
        :id="idDoCampo"
        v-model="valor"
        type="date"
        class="max-w-xs"
        :rotulo="tp('ROTULO.TERMINA')"
        :falta="falta"
      />
      <div v-else-if="campo === 'SEGURADORA'" class="flex flex-col gap-1.5">
        <label :for="idDoCampo" class="text-sm font-medium text-n-slate-12">
          {{ tp('ROTULO.SEGURADORA') }}
        </label>
        <div class="max-w-xs">
          <ChoiceSelect
            v-model="valor"
            :trigger-id="idDoCampo"
            :options="opcoesDeSeguradora"
            :aria-label="tp('ROTULO.SEGURADORA')"
            :invalid="Boolean(falta)"
            :described-by="falta ? idDaFalta : undefined"
          />
        </div>
        <p
          v-if="falta"
          :id="idDaFalta"
          role="alert"
          data-carteira="falta"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ falta }}
        </p>
      </div>
      <CampoDeTelefone
        v-else-if="campo === 'TELEFONE'"
        v-model="valor"
        :label="tp('ROTULO.TELEFONE')"
        :rotulo-do-pais="tp('ROTULO.PAIS')"
        :erro="falta"
      />
      <div
        v-else-if="problema.tipo === 'duplicado'"
        class="grid gap-3 sm:grid-cols-2"
      >
        <button
          v-for="repetida in problema.duplicadas"
          :key="repetida.linha"
          type="button"
          :data-opcao="repetida.linha"
          class="flex flex-col items-start w-full gap-1 p-4 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:enabled:bg-n-alpha-2 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :disabled="ocupado"
          @click="emit('guardar', problema.linha, repetida.linha)"
        >
          <span class="text-base font-medium tabular-nums text-n-slate-12">
            {{ naPlanilha(repetida.valor) }}
          </span>
          <span
            class="flex items-center gap-1 text-sm font-medium text-n-blue-11"
          >
            {{ tp('FICAR_COM_A_LINHA', { linha: repetida.linha }) }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </span>
        </button>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <Button
          v-if="campo"
          type="submit"
          size="lg"
          data-carteira="salvar-problema"
          :label="tp('SALVAR')"
          :disabled="ocupado"
        />
        <template v-if="problema.tipo === 'foto_escura'">
          <Button
            type="button"
            size="lg"
            data-carteira="trocar-o-arquivo"
            :label="tp('TROCAR_O_ARQUIVO')"
            :disabled="ocupado"
            @click="seletorDeArquivo?.click()"
          />
          <input
            ref="seletorDeArquivo"
            type="file"
            class="sr-only"
            tabindex="-1"
            aria-hidden="true"
            :accept="ACEITA_APOLICES"
            @change="trocarOArquivo"
          />
        </template>
        <Button
          v-if="problema.podeSeguirSem"
          slate
          faded
          type="button"
          size="lg"
          data-carteira="seguir-sem-telefone"
          :label="tp('SEGUIR_SEM_TELEFONE')"
          :disabled="ocupado"
          @click="emit('guardar', problema.linha, '')"
        />
        <Button
          v-else
          slate
          faded
          type="button"
          size="lg"
          data-carteira="deixar-de-fora"
          :label="tp('DEIXAR_DE_FORA')"
          :disabled="ocupado"
          @click="emit('deixarDeFora', problema.linha)"
        />
      </div>
    </form>
    <div v-else class="flex flex-wrap items-center justify-between gap-2">
      <p class="flex items-center gap-2 m-0 text-base text-n-slate-11">
        <span
          class="size-5 shrink-0"
          :class="
            guardado
              ? 'i-lucide-circle-check text-n-teal-11'
              : 'i-lucide-circle-minus'
          "
          aria-hidden="true"
        />
        <span>{{ texto }}</span>
        <span class="font-medium text-n-slate-12">
          {{ tp(guardado ? 'PRONTO' : 'DEIXADO') }}
        </span>
      </p>
      <Button
        ghost
        slate
        type="button"
        size="lg"
        data-carteira="voltar-atras"
        :label="tp('VOLTAR_ATRAS')"
        :aria-label="
          tp('VOLTAR_ATRAS_EM', { quem: problema.nome || problema.arquivo })
        "
        :disabled="ocupado"
        @click="emit('reabrir', problema.linha)"
      />
    </div>
  </li>
</template>
