<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import DialogoDaCasa from '../guiada/DialogoDaCasa.vue';
import { useSemFuncao } from '../useSemFuncao';
import DiffDeAcesso from './DiffDeAcesso.vue';

// Apagar uma função (#2308, especificação 5.E). Sem ninguém: diálogo destrutivo simples. Com gente: o destino é
// obrigatório (outra função que quem apaga pode dar, ou "Sem função"), e "Sem função" mostra o que as pessoas ganham
// e perdem. O servidor continua decidindo (destination_required, destination_invalid, changed_meanwhile). Enquanto as
// pessoas carregam ou falharam, o diálogo diz isso e não deixa apagar: nunca "Ninguém usa" sem a contagem. Enquanto
// apaga, fica aberto em "Apagando…", com tudo travado (o destino também); o foco cai no título da lista se o cartão
// sumiu. Quando o servidor faz perguntar de novo com ele aberto, o motivo vai ao role=alert e o foco, ao destino. Sem
// a contagem, o motivo toma o lugar do "não deu para ver quem usa": um alerta só (rodada 6).
const props = defineProps({
  pessoasDa: { type: Function, required: true },
  // 'pronto', 'carregando' ou 'erro': o estado das pessoas na lista.
  estadoDasPessoas: { type: String, default: 'pronto' },
  // Apaga e devolve quando acabou (useApagarFuncao.apagar).
  apagar: { type: Function, required: true },
  focoDeReserva: { type: String, default: '' },
});

const emit = defineEmits(['tentarPessoas']);

const SEM_FUNCAO = 'none';

const { t } = useI18n();
const { reachesRole } = usePeopleAccess();
const { diff, semFuncaoTravado } = useSemFuncao();
const funcoes = useMapGetter('customRole/getCustomRoles');

const dialogo = ref(null);
const funcao = ref(null);
const destino = ref('');
const erro = ref('');
const apagando = ref(false);
const campo = useId();
// Cada abrir() conta: se o servidor recusou e a tela perguntou de novo, o diálogo continua aberto.
let vez = 0;

const quantas = computed(() =>
  funcao.value ? props.pessoasDa(funcao.value).length : 0
);
const semContagem = computed(() => props.estadoDasPessoas !== 'pronto');

const comGente = computed(() => quantas.value > 0);
// O campo do destino só aparece com a contagem pronta e gente na função; fora dele, o motivo de ter voltado (a recusa
// do servidor) vai para o alto do diálogo (revisão do #2308, rodada 5).
const comDestino = computed(() => !semContagem.value && comGente.value);
const nome = computed(() => funcao.value?.name || '');

const opcoes = computed(() => [
  ...funcoes.value
    .filter(item => item.id !== funcao.value?.id && reachesRole(item))
    .map(item => ({ value: item.id, label: item.name })),
  // "Sem função" segue a mesma régua de dar uma função (#2317): fora do alcance, aparece travada, com o motivo.
  {
    value: SEM_FUNCAO,
    label: t('FUNCOES_EQUIPE.APAGAR.SEM_FUNCAO'),
    ...(semFuncaoTravado.value && {
      disabled: true,
      hint: t(
        'FUNCOES_EQUIPE.APAGAR.SEM_FUNCAO_TRAVADA',
        { n: quantas.value },
        quantas.value
      ),
    }),
  },
]);

const mudanca = computed(() => diff(funcao.value?.permissions));

const textos = computed(() =>
  comGente.value
    ? {
        titulo: t(
          'FUNCOES_EQUIPE.APAGAR.PARA_ONDE',
          { n: quantas.value },
          quantas.value
        ),
        texto: t(
          'FUNCOES_EQUIPE.APAGAR.PARA_ONDE_TEXTO',
          { nome: nome.value },
          quantas.value
        ),
        seguro: t('FUNCOES_EQUIPE.APAGAR.MANTER_FUNCAO'),
        acao: t('FUNCOES_EQUIPE.APAGAR.MOVER'),
      }
    : {
        titulo: t('FUNCOES_EQUIPE.APAGAR.TITULO', { nome: nome.value }),
        texto: semContagem.value ? '' : t('FUNCOES_EQUIPE.APAGAR.TEXTO'),
        seguro: t('FUNCOES_EQUIPE.APAGAR.MANTER'),
        acao: t('FUNCOES_EQUIPE.APAGAR.APAGAR'),
      }
);

// `mensagem`: a recusa do servidor ao reabrir (a função escolhida sumiu ou saiu do alcance, ainda tem gente). Quem
// reabre no meio do apagar é a recusa: o servidor já respondeu, e o destino destrava para receber o foco.
const abrir = (funcaoParaApagar, mensagem = '') => {
  vez += 1;
  apagando.value = false;
  funcao.value = funcaoParaApagar;
  destino.value = '';
  erro.value = mensagem;
  dialogo.value?.abrir();
};

const confirmar = async () => {
  if (apagando.value) return;
  const minhaVez = vez;
  apagando.value = true;
  await props.apagar({
    funcao: funcao.value,
    destino: comGente.value ? destino.value : undefined,
  });
  apagando.value = false;
  if (minhaVez === vez) dialogo.value?.fechar();
};

// "Tentar de novo" some quando as pessoas voltam a carregar: o foco vai ao título do diálogo, que fica. O aviso de
// antes sai junto: com as pessoas de volta, o destino não abre com um erro velho (rodada 6).
const tentarPessoas = () => {
  erro.value = '';
  emit('tentarPessoas');
  dialogo.value?.focarTitulo();
};

defineExpose({ abrir });
</script>

<template>
  <DialogoDaCasa
    ref="dialogo"
    tipo="destrutivo"
    v-bind="textos"
    :acao-desabilitada="semContagem || (comGente && destino === '')"
    :fecha-na-acao="false"
    :ocupado="apagando"
    :acao-ocupada="$t('FUNCOES_EQUIPE.APAGAR.APAGANDO')"
    :foco-de-reserva="focoDeReserva"
    :foco-ao-reabrir="`#${campo}`"
    @acao="confirmar"
  >
    <p
      v-if="erro && !comDestino && estadoDasPessoas !== 'erro'"
      data-erro-apagar
      role="alert"
      class="m-0 text-sm text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <p
      v-if="estadoDasPessoas === 'carregando'"
      data-apagar-carregando
      role="status"
      class="m-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('FUNCOES_EQUIPE.APAGAR.VENDO_QUEM') }}
    </p>
    <div
      v-else-if="estadoDasPessoas === 'erro'"
      data-apagar-erro
      class="flex flex-wrap items-center gap-2"
    >
      <p role="alert" class="m-0 text-[0.9375rem] text-n-ruby-11">
        {{ erro || $t('FUNCOES_EQUIPE.APAGAR.SEM_PESSOAS') }}
      </p>
      <button
        type="button"
        data-apagar-tentar
        class="px-1 font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="tentarPessoas"
      >
        {{ $t('FUNCOES_EQUIPE.ERRO.TENTAR') }}
      </button>
    </div>
    <div v-else-if="comDestino" data-destino class="flex flex-col gap-3 mt-1">
      <label :for="campo" class="text-sm font-semibold text-n-slate-12">
        {{ $t('FUNCOES_EQUIPE.APAGAR.NOVA_FUNCAO') }}
      </label>
      <ChoiceSelect
        v-model="destino"
        :trigger-id="campo"
        :options="opcoes"
        :aria-label="$t('FUNCOES_EQUIPE.APAGAR.NOVA_FUNCAO')"
        :placeholder="$t('FUNCOES_EQUIPE.APAGAR.ESCOLHA')"
        :invalid="Boolean(erro)"
        :disabled="apagando"
        class="w-full"
        @change="erro = ''"
      />
      <p
        v-if="erro"
        data-erro-destino
        role="alert"
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
      <DiffDeAcesso
        v-if="destino === SEM_FUNCAO"
        :ganha="mudanca.ganha"
        :perde="mudanca.perde"
        :pessoas="quantas"
      />
    </div>
  </DialogoDaCasa>
</template>
