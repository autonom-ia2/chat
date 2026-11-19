<script setup>
import { computed, ref, useId, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
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
// de marcar com a cor dela. O título diz para quantas pessoas é, e o botão
// também ("Tirar de 3 pessoas"), contando quem veio de "Marcar todas".
// Trocar entre Colocar e Tirar zera a escolha: a etiqueta marcada num modo não
// vai sozinha para o outro. "Tirar" lista só as etiquetas que as marcadas têm,
// com quantas têm cada uma ("site · 1 pessoa"), inclusive etiqueta que a conta
// já apagou. Tirou tudo certo: em vez do aviso que some, a página mostra o aviso
// com "Desfazer" (evento `tirou`), que recoloca cada etiqueta em quem a tinha.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido', 'tirou']);

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
watch(escolhidas, () => {
  faltaEscolher.value = false;
});
watch(modo, () => {
  escolhidas.value = [];
});

const ehTirar = computed(() => modo.value === TIRAR);
const quantasPessoas = computed(() => props.pessoas.length);

// As etiquetas que as marcadas têm, com quantas têm cada uma. A cor vem da
// conta; a etiqueta que a conta apagou fica com o ponto neutro.
const etiquetasDasMarcadas = computed(() => {
  const cores = new Map(etiquetas.value.map(({ nome, cor }) => [nome, cor]));
  const contagem = props.pessoas
    .flatMap(pessoa => pessoa.labels ?? [])
    .reduce(
      (porNome, nome) => ({ ...porNome, [nome]: (porNome[nome] ?? 0) + 1 }),
      {}
    );
  return Object.entries(contagem)
    .map(([nome, quantas]) => ({ nome, cor: cores.get(nome), quantas }))
    .sort((a, b) => a.nome.localeCompare(b.nome));
});
const opcoes = computed(() =>
  ehTirar.value ? etiquetasDasMarcadas.value : etiquetas.value
);

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

// Para o "Desfazer": cada etiqueta tirada que a conta ainda tem, com quem a
// tinha. A que a conta apagou não tem como voltar (o servidor só coloca
// etiqueta da conta).
const paraDevolver = () => {
  const daConta = new Set(etiquetas.value.map(({ nome }) => nome));
  return escolhidas.value
    .filter(nome => daConta.has(nome))
    .map(nome => ({
      etiqueta: nome,
      ids: props.pessoas
        .filter(pessoa => (pessoa.labels ?? []).includes(nome))
        .map(({ id }) => id),
    }))
    .filter(({ ids }) => ids.length);
};

const aplicar = async () => {
  if (!escolhidas.value.length) {
    faltaEscolher.value = true;
    lista.value?.querySelector('input')?.focus();
    return;
  }
  const devolver = ehTirar.value ? paraDevolver() : [];
  const feito = await enviarOQueFalta(props.pessoas, agir);
  if (!feito || feito.erro || feito.deFora.length) return;
  const frase = feita(feito.feitas);
  if (ehTirar.value && feito.feitas) emit('tirou', { frase, devolver });
  else useAlert(frase);
  dialogo.value?.close();
};

// Conta sem etiqueta e ninguém marcado com etiqueta: não há o que escolher nos
// dois modos, o botão só fecha. Num modo só sem opção, o aviso é do modo.
const semEtiquetas = computed(
  () => !etiquetas.value.length && !etiquetasDasMarcadas.value.length
);
const semOpcoes = computed(() => !opcoes.value.length);
const aoConfirmar = () =>
  terminou.value || semOpcoes.value ? dialogo.value?.close() : aplicar();

const rotuloDoBotao = computed(() => {
  if (semOpcoes.value) return t('RELACIONAMENTOS.COMUM.FECHAR');
  return t(
    `${ET}.BOTAO_${ehTirar.value ? 'TIRAR' : 'COLOCAR'}`,
    { count: quantasPessoas.value },
    quantasPessoas.value
  );
});

const MODOS = [
  { id: COLOCAR, chave: 'COLOCAR', icone: 'i-lucide-plus' },
  { id: TIRAR, chave: 'TIRAR', icone: 'i-lucide-minus' },
];

defineExpose({ abrir });
</script>

<template>
  <Dialog ref="dialogo" type="edit" width="md" @close="fechar">
    <TituloDoDialogo
      :titulo="t(`${ET}.TITULO`)"
      :aviso="t(`${ET}.PARA_QUEM`, { count: quantasPessoas }, quantasPessoas)"
    />
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
          <p
            v-if="semOpcoes"
            data-relacionamentos="sem-opcoes"
            class="m-0 text-sm text-n-slate-11"
          >
            {{ t(`${ET}.${ehTirar ? 'NINGUEM_TEM' : 'SEM_ETIQUETAS'}`) }}
          </p>
          <ul
            v-else
            ref="lista"
            class="flex flex-col p-1 m-0 overflow-y-auto list-none border rounded-xl max-h-64 border-n-weak"
            data-relacionamentos="etiquetas"
          >
            <li v-for="etiqueta in opcoes" :key="etiqueta.nome">
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
                <span
                  v-if="ehTirar"
                  data-relacionamentos="quantas-tem"
                  class="text-sm text-n-slate-11 shrink-0"
                >
                  ·
                  {{
                    t(
                      `${ET}.QUANTAS`,
                      { count: etiqueta.quantas },
                      etiqueta.quantas
                    )
                  }}
                </span>
              </label>
            </li>
          </ul>
          <p
            v-if="!semOpcoes"
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
    <!-- #3062 — "Colocar em 12 pessoas" não cabe ao lado do "Cancelar" no
    celular: lá os dois botões ficam um embaixo do outro, o de confirmar em
    cima. Sem campo de texto no diálogo, o Enter não tem o que enviar: o botão
    confirma pelo clique. -->
    <template #footer>
      <div class="flex flex-col-reverse w-full gap-3 sm:flex-row">
        <Button
          v-if="!terminou && !semOpcoes"
          slate
          faded
          type="button"
          class="w-full"
          data-cancelar
          :label="rotuloDeCancelar(t, resultado)"
          @click="dialogo?.close()"
        />
        <Button
          type="button"
          class="w-full"
          data-confirmar
          :label="rotuloDeConfirmar(t, resultado, rotuloDoBotao)"
          :is-loading="enviando"
          :disabled="enviando"
          @click="aoConfirmar"
        />
      </div>
    </template>
  </Dialog>
</template>
