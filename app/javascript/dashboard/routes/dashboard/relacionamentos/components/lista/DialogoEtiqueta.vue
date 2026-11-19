<script setup>
import { computed, ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import ResultadoDaAcao from './ResultadoDaAcao.vue';
import {
  resumoDoQueFoiFeito,
  rotuloDeCancelar,
  rotuloDeConfirmar,
  useEnvioEmFatias,
} from '../../lista/useEnvioEmFatias';

// #2894 — diálogo pequeno: escolher etiquetas e colocar nas pessoas marcadas.
// Nada vem escolhido, e o botão está sempre ligado: sem escolha, o clique não
// fecha, diz o que falta e leva o foco à primeira etiqueta. Enquanto age: "50
// de 120". Deu tudo certo: avisa e fecha. Se alguém ficou de fora ou parou no
// meio, o diálogo fica aberto e diz quem, por quê e quantas ainda não foram.
// #3062 — como a lista de contatos de hoje: várias etiquetas de uma vez, e
// "Colocar" ou "Tirar" no alto (abre em "Colocar"). Cada etiqueta é uma caixa
// de marcar com a cor dela; o botão diz quantas e o quê ("Tirar 2 etiquetas").
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const COLOCAR = 'colocar';
const TIRAR = 'tirar';
const ET = 'RELACIONAMENTOS.LISTA.ETIQUETA';

const { t, locale } = useI18n();
const dialogo = useTemplateRef('dialogo');
const lista = useTemplateRef('lista');
const idDoModo = useId();
const idDaPergunta = useId();
const idDoAviso = useId();

const etiquetas = ref([]);
const modo = ref(COLOCAR);
const escolhidas = ref([]);
const faltaEscolher = ref(false);
watch([escolhidas, modo], () => {
  faltaEscolher.value = false;
});

const ehTirar = computed(() => modo.value === TIRAR);

// “feira” e “site”, na língua do painel.
const nomesEscolhidos = () =>
  new Intl.ListFormat(locale.value.replace('_', '-'), {
    type: 'conjunction',
  }).format(escolhidas.value.map(nome => `“${nome}”`));

const feita = count =>
  t(
    `${ET}.${ehTirar.value ? 'TIRADA' : 'APLICADA'}`,
    { count, etiquetas: nomesEscolhidos() },
    count
  );

const {
  enviando,
  andamento,
  resultado,
  terminou,
  enviarOQueFalta,
  fechar,
  recomecar,
} = useEnvioEmFatias({
  contagem: () => (ehTirar.value ? 'tiradas' : 'aplicadas'),
  mensagemDeErro: () => t(`${ET}.ERRO`),
  aoConcluir: faltam => emit('concluido', faltam),
  resumo: resumoDoQueFoiFeito(t, feita),
});

const marcada = nome => escolhidas.value.includes(nome);
const alternar = nome => {
  escolhidas.value = marcada(nome)
    ? escolhidas.value.filter(item => item !== nome)
    : [...escolhidas.value, nome];
};

const abrir = async () => {
  // Abriu de novo com o envio ainda rodando: só mostra o andamento; a escolha
  // fica como estava.
  if (!recomecar()) {
    dialogo.value?.open();
    return;
  }
  modo.value = COLOCAR;
  escolhidas.value = [];
  faltaEscolher.value = false;
  try {
    etiquetas.value = await props.acoes.etiquetas();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
    return;
  }
  dialogo.value?.open();
};

const agir = lote => {
  const comEtiquetas = { ...lote, etiquetas: escolhidas.value };
  return ehTirar.value
    ? props.acoes.tirarEtiqueta(comEtiquetas)
    : props.acoes.aplicarEtiqueta(comEtiquetas);
};

const aplicar = async () => {
  if (!escolhidas.value.length) {
    faltaEscolher.value = true;
    lista.value?.querySelector('input')?.focus();
    return;
  }
  const feito = await enviarOQueFalta(props.pessoas, agir);
  if (!feito || feito.erro || feito.deFora.length) return;
  useAlert(feita(feito.feitas));
  dialogo.value?.close();
};

// Conta sem etiqueta nenhuma: não há o que escolher, o botão só fecha.
const semEtiquetas = computed(() => !etiquetas.value.length);
const aoConfirmar = () =>
  terminou.value || semEtiquetas.value ? dialogo.value?.close() : aplicar();

const rotuloDoBotao = computed(() => {
  if (semEtiquetas.value) return t('RELACIONAMENTOS.COMUM.FECHAR');
  const quantas = escolhidas.value.length;
  return t(
    `${ET}.BOTAO_${ehTirar.value ? 'TIRAR' : 'COLOCAR'}`,
    { count: quantas },
    quantas
  );
});

const MODOS = [
  { id: COLOCAR, chave: 'COLOCAR', icone: 'i-lucide-plus' },
  { id: TIRAR, chave: 'TIRAR', icone: 'i-lucide-minus' },
];

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="rotuloDeConfirmar(t, resultado, rotuloDoBotao)"
    :cancel-button-label="rotuloDeCancelar(t, resultado)"
    :show-cancel-button="!terminou && !semEtiquetas"
    :is-loading="enviando"
    @confirm="aoConfirmar"
    @close="fechar"
  >
    <TituloDoDialogo :titulo="t(`${ET}.TITULO`)" />
    <div data-relacionamentos="dialogo-etiqueta" class="flex flex-col gap-5">
      <ResultadoDaAcao
        :andamento="andamento"
        :resultado="resultado"
        :frase="feita"
      />
      <p
        v-if="!resultado && semEtiquetas"
        data-relacionamentos="sem-etiquetas"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${ET}.SEM_ETIQUETAS`) }}
      </p>
      <template v-else-if="!resultado">
        <fieldset class="p-0 m-0 border-0 min-w-0">
          <legend :id="idDoModo" class="sr-only">{{ t(`${ET}.MODO`) }}</legend>
          <div
            class="grid grid-cols-2 gap-1 p-1 rounded-xl bg-n-alpha-1"
            data-relacionamentos="modo-da-etiqueta"
          >
            <label
              v-for="item in MODOS"
              :key="item.id"
              class="relative flex items-center justify-center gap-2 px-3 text-sm font-medium transition-colors rounded-lg cursor-pointer min-h-11 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
              :class="
                modo === item.id
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
            >
              <input
                v-model="modo"
                type="radio"
                class="sr-only"
                :name="idDoModo"
                :value="item.id"
                :data-modo="item.id"
              />
              <span :class="item.icone" class="size-4" aria-hidden="true" />
              {{ t(`${ET}.${item.chave}`) }}
            </label>
          </div>
        </fieldset>
        <fieldset
          class="flex flex-col min-w-0 gap-2 p-0 m-0 border-0"
          :aria-describedby="idDoAviso"
        >
          <legend
            :id="idDaPergunta"
            class="mb-2 text-sm font-medium text-n-slate-12"
          >
            {{ t(`${ET}.PERGUNTA_${ehTirar ? 'TIRAR' : 'COLOCAR'}`) }}
          </legend>
          <ul
            ref="lista"
            class="flex flex-col p-1 m-0 overflow-y-auto list-none border rounded-xl max-h-64 border-n-weak"
            data-relacionamentos="etiquetas"
          >
            <li v-for="etiqueta in etiquetas" :key="etiqueta.nome">
              <label
                class="flex items-center gap-3 px-3 rounded-lg cursor-pointer min-h-11 hover:bg-n-alpha-1"
                :class="{ 'bg-n-alpha-1': marcada(etiqueta.nome) }"
              >
                <Checkbox
                  :model-value="marcada(etiqueta.nome)"
                  :data-etiqueta="etiqueta.nome"
                  @change="alternar(etiqueta.nome)"
                />
                <span
                  class="rounded-full size-2.5 shrink-0 bg-n-slate-8"
                  :style="etiqueta.cor ? { backgroundColor: etiqueta.cor } : {}"
                  aria-hidden="true"
                />
                <span class="text-sm truncate text-n-slate-12">
                  {{ etiqueta.nome }}
                </span>
              </label>
            </li>
          </ul>
          <p
            :id="idDoAviso"
            role="alert"
            data-relacionamentos="etiqueta-falta"
            class="m-0 text-sm text-n-ruby-11"
          >
            {{ faltaEscolher ? t(`${ET}.FALTA_ESCOLHER`) : '' }}
          </p>
        </fieldset>
      </template>
    </div>
  </Dialog>
</template>
