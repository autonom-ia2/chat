<script setup>
import { computed } from 'vue';
import {
  CONVERSATION_LEVELS,
  getLevel,
  levelOptions,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import { travaDoNivel } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA, motivoDaTrava } from '../motivoDaTrava';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import EscolhaDeNivel from './EscolhaDeNivel.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Conversas (#2308, especificação 5.B3): Nenhuma / Só olha / Atende as próprias / Atende todas. Em "Atende as
// próprias", as duas subescolhas por dentro; pelo menos uma fica ligada (regra do toggleExtra). "Quem recebe cada
// conversa nova" (ASSIGNMENT) mora aqui.
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  quem: { type: String, required: true },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t } = useTextos();

const conversas = moduleByKey('CONVERSATIONS');
const quemRecebe = moduleByKey('ASSIGNMENT');
const OPCAO = {
  [CONVERSATION_LEVELS.NONE]: 'NENHUMA',
  [CONVERSATION_LEVELS.VIEW]: 'SO_OLHA',
  [CONVERSATION_LEVELS.LIMITED]: 'PROPRIAS',
  [CONVERSATION_LEVELS.ALL]: 'TODAS',
};
const LER_COLEGAS = 'conversation_view';
const SUBESCOLHAS = [
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

const textoDaTrava = motivo =>
  motivo ? t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[motivo]}`) : '';

const nivel = computed(() => getLevel(conversas, props.permissions));
const opcoes = computed(() =>
  levelOptions(conversas).map(valor => ({
    valor,
    titulo: t(`FUNCOES_EQUIPE.CONVERSAS.${OPCAO[valor]}.TITULO`),
    dica: t(`FUNCOES_EQUIPE.CONVERSAS.${OPCAO[valor]}.DICA`),
    trava:
      valor === nivel.value
        ? ''
        : textoDaTrava(travaDoNivel(props.giver, conversas, valor)),
  }))
);

// "Também lê as dos colegas" só aparece ligada (salva pela tela de hoje), para dar para desligar.
const subescolhas = computed(() => [
  ...SUBESCOLHAS,
  ...(props.permissions.includes(LER_COLEGAS) ? [LER_COLEGAS] : []),
]);
const travaDaSubescolha = chave =>
  props.permissions.includes(chave)
    ? ''
    : textoDaTrava(motivoDaTrava(props.giver, chave));

const atualizar = permissions => emit('update:permissions', permissions);
const escolher = valor =>
  atualizar(setLevel(conversas, valor, props.permissions));
const alternar = chave =>
  atualizar(toggleExtra(conversas, chave, props.permissions));

const estadoDeQuemRecebe = computed(() =>
  props.permissions.includes('assignment_manage')
    ? t('FUNCOES_EQUIPE.CONVERSAS.QUEM_RECEBE.MEXE')
    : t('FUNCOES_EQUIPE.CONVERSAS.QUEM_RECEBE.NAO_MEXE')
);
</script>

<template>
  <PerguntaDaFuncao
    :titulo="$t('FUNCOES_EQUIPE.CONVERSAS.TITULO', { quem })"
    :dica="$t('FUNCOES_EQUIPE.CONVERSAS.DICA')"
    @pronto="emit('pronto')"
  >
    <EscolhaDeNivel
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="$t('FUNCOES_EQUIPE.CONVERSAS.TITULO', { quem })"
      @update:model-value="escolher"
    >
      <template #dentro="{ valor }">
        <div
          v-if="valor === CONVERSATION_LEVELS.LIMITED"
          class="flex flex-col divide-y divide-n-blue-6"
        >
          <InterruptorDaLinha
            v-for="chave in subescolhas"
            :key="chave"
            :titulo="$t(`FUNCOES_EQUIPE.CONVERSAS.EXTRAS.${chave}.TITULO`)"
            :texto="$t(`FUNCOES_EQUIPE.CONVERSAS.EXTRAS.${chave}.TEXTO`)"
            :ligado="permissions.includes(chave)"
            :trava="travaDaSubescolha(chave)"
            class="!ps-0"
            @alternar="alternar(chave)"
          />
        </div>
      </template>
    </EscolhaDeNivel>
    <LinhaRecolhida
      icone="i-lucide-shuffle"
      :titulo="$t('FUNCOES_EQUIPE.CONVERSAS.QUEM_RECEBE.TITULO')"
      :estado="estadoDeQuemRecebe"
    >
      <AreaEmLinha
        :module="quemRecebe"
        :permissions="permissions"
        :inicial="inicial"
        :giver="giver"
        @update:permissions="atualizar"
      />
    </LinhaRecolhida>
  </PerguntaDaFuncao>
</template>
