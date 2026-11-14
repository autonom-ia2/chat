<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  DESTINOS,
  campoDaColuna,
  chaveDaColuna,
  destinosDisponiveis,
} from '../../trazer/destinos';
import CampoDaInformacao from './CampoDaInformacao.vue';

// #2894 — uma coluna da planilha e para onde ela vai (“Cel” fica como
// Telefone), com Trocar. Coluna que o sistema não conhecia vira "informação da pessoa" e
// ganha também Não guardar.
// #2896 — a troca sai com a chave da coluna (o índice, quando vem do servidor).
// Coluna sem título na planilha aparece pela posição: "Coluna 5".
// Fatia 2 — a coluna que é "informação nova" mostra o campo dela (o nome e o
// "Para que serve?"), que sai junto com o destino. Escolher "Informação nova"
// numa coluna com título salva na hora, com o título como nome do campo; numa
// coluna sem título a troca espera a pessoa escrever o nome. `temEmpresa`: sem
// empresa na leitura, "Telefone da empresa" não é oferecido.
// `recusa` (`{ chave }`): a troca que o servidor não aceitou (ou que falhou)
// fica dita aqui, como alerta, e o foco volta ao "Mudar" (ou ao nome da
// informação nova). `relendo`: a planilha está sendo lida de novo; a linha que
// pediu a troca mostra o botão carregando e a frase ao lado (quem anuncia ao
// leitor de tela é o `status` da tela de conferir). A coluna que o sistema não
// tem certeza de onde vai (`duvidosa`) pede para a pessoa conferir.
const props = defineProps({
  coluna: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
  temEmpresa: { type: Boolean, default: true },
  // #2897 — destinos que só existem em quem usa (os de seguro), já com o nome
  // que a tela dá a cada um: `{ value, label }`.
  destinosAMais: { type: Array, default: () => [] },
});
const emit = defineEmits(['trocar']);

const { t } = useI18n();
const CHAVES_DOS_DESTINOS = {
  [DESTINOS.NOME]: 'RELACIONAMENTOS_TRAZER.DESTINOS.NOME',
  [DESTINOS.TELEFONE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.TELEFONE',
  [DESTINOS.TELEFONE_DA_EMPRESA]:
    'RELACIONAMENTOS_TRAZER.DESTINOS.TELEFONE_DA_EMPRESA',
  [DESTINOS.EMAIL]: 'RELACIONAMENTOS_TRAZER.DESTINOS.EMAIL',
  [DESTINOS.EMPRESA]: 'RELACIONAMENTOS_TRAZER.DESTINOS.EMPRESA',
  [DESTINOS.CIDADE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.CIDADE',
  [DESTINOS.CLIENTE]: 'RELACIONAMENTOS_TRAZER.DESTINOS.CLIENTE',
  [DESTINOS.INFORMACAO]: 'RELACIONAMENTOS_TRAZER.DESTINOS.INFORMACAO',
  [DESTINOS.NAO_GUARDAR]: 'RELACIONAMENTOS_TRAZER.DESTINOS.NAO_GUARDAR',
};
const trocando = ref(false);
const raiz = ref(null);
const escolha = ref(null);
const caixaDaEscolha = ref(null);
const campo = ref(null);
// A pessoa escolheu "Informação nova" e ainda falta o nome do campo.
const querInformacao = ref(false);
// Esta linha pediu a troca que está indo ao servidor.
const pediuATroca = ref(false);

const nomeDoDestino = destino =>
  props.destinosAMais.find(({ value }) => value === destino)?.label ??
  t(CHAVES_DOS_DESTINOS[destino]);

const nome = computed(
  () =>
    props.coluna.nome ||
    t('RELACIONAMENTOS_TRAZER.GUARDAR.COLUNA_SEM_NOME', {
      numero: (props.coluna.indice ?? 0) + 1,
    })
);

const opcoes = computed(() => [
  ...destinosDisponiveis(props.temEmpresa).map(destino => ({
    value: destino,
    label: nomeDoDestino(destino),
  })),
  ...props.destinosAMais,
]);

const naoGuarda = computed(() => props.coluna.destino === DESTINOS.NAO_GUARDAR);
const virouInformacao = computed(
  () => props.coluna.destino === DESTINOS.INFORMACAO
);
const dizQuemEhCliente = computed(
  () => props.coluna.destino === DESTINOS.CLIENTE
);
const pendente = computed(() => querInformacao.value && !virouInformacao.value);
const mostraCampo = computed(() => virouInformacao.value || pendente.value);

// Devolve o foco ao "Trocar" — só se o foco ainda está aqui ou se perdeu (no
// corpo da página); quem clicou em outro campo não é arrastado de volta.
const voltarAoTrocar = async () => {
  await nextTick();
  const ativo = document.activeElement;
  const perdeu = !ativo || ativo === document.body;
  if (!perdeu && !raiz.value?.contains(ativo)) return;
  raiz.value?.querySelector('[data-relacionamentos="trocar-coluna"]')?.focus();
};

const sairDaTroca = () => {
  trocando.value = false;
  voltarAoTrocar();
};

const trocar = (...troca) => {
  pediuATroca.value = true;
  emit('trocar', chaveDaColuna(props.coluna), ...troca);
};
const trocarParaInformacao = doCampo => trocar(DESTINOS.INFORMACAO, doCampo);

// Sem título na coluna não há nome para o campo: a troca fica esperando, com o
// foco no campo do nome.
const pedirONome = async () => {
  querInformacao.value = true;
  trocando.value = false;
  await nextTick();
  campo.value?.focarNome();
};

const escolher = destino => {
  const mudou = destino !== props.coluna.destino;
  const doTitulo = campoDaColuna(props.coluna);
  if (mudou && destino === DESTINOS.INFORMACAO && !doTitulo.nome) {
    pedirONome();
    return;
  }
  querInformacao.value = false;
  sairDaTroca();
  if (!mudou) return;
  if (destino === DESTINOS.INFORMACAO) trocarParaInformacao(doTitulo);
  else trocar(destino);
};

// A recusa chega com a escrita ainda em voo (o "Mudar" desligado não recebe
// foco): o foco volta quando ela termina.
let faltaDevolverOFoco = false;
const devolverOFoco = async () => {
  if (!faltaDevolverOFoco || props.ocupado) return;
  faltaDevolverOFoco = false;
  await nextTick();
  if (mostraCampo.value) campo.value?.focarNome();
  else {
    raiz.value
      ?.querySelector('[data-relacionamentos="trocar-coluna"]')
      ?.focus();
  }
};
watch(
  () => props.recusa,
  recusa => {
    faltaDevolverOFoco = Boolean(recusa);
    devolverOFoco();
  }
);
watch(
  () => props.ocupado,
  ocupado => {
    if (!ocupado) pediuATroca.value = false;
    devolverOFoco();
  }
);

// Ao abrir a troca, a lista já vem aberta e com o foco no gatilho.
const abrirTroca = async () => {
  trocando.value = true;
  await nextTick();
  escolha.value?.abrir();
};

// O ChoiceSelect não avisa quando fecha; o `aria-expanded` do gatilho avisa.
// Fechou sem escolha (Esc, clique fora, mesma opção): volta ao estado normal.
let observador = null;
let jaAbriu = false;
const observarFechamento = caixa => {
  observador?.disconnect();
  observador = null;
  jaAbriu = false;
  if (!caixa) return;
  observador = new MutationObserver(() => {
    const aberta = caixa
      .querySelector('[aria-expanded]')
      ?.getAttribute('aria-expanded');
    if (aberta === 'true') jaAbriu = true;
    else if (jaAbriu) sairDaTroca();
  });
  observador.observe(caixa, {
    attributes: true,
    attributeFilter: ['aria-expanded'],
    subtree: true,
  });
};
watch(caixaDaEscolha, observarFechamento);
onBeforeUnmount(() => observador?.disconnect());
</script>

<template>
  <li
    ref="raiz"
    :data-coluna="nome"
    class="flex flex-wrap items-center justify-between gap-3 py-3"
  >
    <div class="flex flex-col gap-1">
      <p
        class="flex flex-wrap items-center gap-2 m-0 text-base text-n-slate-12"
      >
        <template v-if="naoGuarda">
          {{
            t('RELACIONAMENTOS_TRAZER.GUARDAR.NAO_VOU_GUARDAR', {
              coluna: nome,
            })
          }}
        </template>
        <template v-else-if="virouInformacao">
          {{
            t('RELACIONAMENTOS_TRAZER.GUARDAR.FICA_COMO_INFORMACAO', {
              coluna: nome,
            })
          }}
        </template>
        <template v-else-if="dizQuemEhCliente">
          {{
            t('RELACIONAMENTOS_TRAZER.GUARDAR.DIZ_QUEM_E_CLIENTE', {
              coluna: nome,
            })
          }}
        </template>
        <template v-else>
          {{
            t('RELACIONAMENTOS_TRAZER.GUARDAR.FICA_COMO', {
              coluna: nome,
              destino: nomeDoDestino(coluna.destino),
            })
          }}
        </template>
      </p>
      <p
        v-if="coluna.duvidosa"
        data-relacionamentos="coluna-duvidosa"
        class="flex items-center gap-1 m-0 text-sm font-medium text-n-amber-11"
      >
        <span
          class="i-lucide-circle-alert size-4 shrink-0"
          aria-hidden="true"
        />
        {{ t('RELACIONAMENTOS_TRAZER.GUARDAR.DUVIDOSA') }}
      </p>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <div v-if="trocando" ref="caixaDaEscolha" class="w-64 max-w-full">
        <ChoiceSelect
          ref="escolha"
          :model-value="coluna.destino"
          :options="opcoes"
          :aria-label="
            t('RELACIONAMENTOS_TRAZER.GUARDAR.ROTULO_TROCAR', {
              coluna: nome,
            })
          "
          @update:model-value="escolher"
        />
      </div>
      <Button
        v-else
        faded
        slate
        data-relacionamentos="trocar-coluna"
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.TROCAR')"
        :aria-label="
          t('RELACIONAMENTOS_TRAZER.GUARDAR.ROTULO_MUDAR', {
            coluna: nome,
          })
        "
        :disabled="ocupado"
        :is-loading="pediuATroca && ocupado"
        @click="abrirTroca"
      />
      <Button
        v-if="virouInformacao && !trocando"
        faded
        slate
        class="min-h-11"
        :label="t('RELACIONAMENTOS_TRAZER.GUARDAR.NAO_GUARDAR')"
        :disabled="ocupado"
        @click="escolher(DESTINOS.NAO_GUARDAR)"
      />
      <span
        v-if="pediuATroca && relendo"
        data-relacionamentos="relendo-a-coluna"
        aria-hidden="true"
        class="text-sm text-n-slate-11"
      >
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.RELENDO') }}
      </span>
    </div>
    <p
      v-if="recusa"
      data-relacionamentos="recusa-da-coluna"
      role="alert"
      class="w-full m-0 text-sm font-medium text-n-ruby-11"
    >
      {{ t(recusa.chave) }}
    </p>
    <div v-if="mostraCampo" class="w-full">
      <CampoDaInformacao
        ref="campo"
        :coluna="coluna"
        :ocupado="ocupado"
        :pendente="pendente"
        @salvar="trocarParaInformacao"
      />
    </div>
  </li>
</template>
