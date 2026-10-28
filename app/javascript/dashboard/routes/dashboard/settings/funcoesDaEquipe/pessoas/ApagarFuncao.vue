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
// e perdem. O servidor continua decidindo (destination_required, destination_invalid, changed_meanwhile).
const emit = defineEmits(['apagar']);

const SEM_FUNCAO = 'none';

const { t } = useI18n();
const { reachesRole } = usePeopleAccess();
const { diff } = useSemFuncao();
const funcoes = useMapGetter('customRole/getCustomRoles');

const dialogo = ref(null);
const funcao = ref(null);
const quantas = ref(0);
const destino = ref('');
const erro = ref('');
const campo = useId();

const comGente = computed(() => quantas.value > 0);
const nome = computed(() => funcao.value?.name || '');

const opcoes = computed(() => [
  ...funcoes.value
    .filter(item => item.id !== funcao.value?.id && reachesRole(item))
    .map(item => ({ value: item.id, label: item.name })),
  { value: SEM_FUNCAO, label: t('FUNCOES_EQUIPE.APAGAR.SEM_FUNCAO') },
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
        texto: t('FUNCOES_EQUIPE.APAGAR.TEXTO'),
        seguro: t('FUNCOES_EQUIPE.APAGAR.MANTER'),
        acao: t('FUNCOES_EQUIPE.APAGAR.APAGAR'),
      }
);

// `mensagem`: a recusa do servidor ao reabrir (a função escolhida sumiu ou saiu do alcance).
const abrir = (funcaoParaApagar, pessoas, mensagem = '') => {
  funcao.value = funcaoParaApagar;
  quantas.value = pessoas;
  destino.value = '';
  erro.value = mensagem;
  dialogo.value?.abrir();
};

const confirmar = () =>
  emit('apagar', {
    funcao: funcao.value,
    destino: comGente.value ? destino.value : undefined,
  });

defineExpose({ abrir });
</script>

<template>
  <DialogoDaCasa
    ref="dialogo"
    tipo="destrutivo"
    v-bind="textos"
    :acao-desabilitada="comGente && destino === ''"
    @acao="confirmar"
  >
    <div v-if="comGente" data-destino class="flex flex-col gap-3 mt-1">
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
