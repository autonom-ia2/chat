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
import { areasDentroDe, travaDoNivel } from '../areasDaFuncao';
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
  nome: { type: String, default: '' },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, quemFor } = useTextos();

const conversas = moduleByKey('CONVERSATIONS');
const [quemRecebe] = areasDentroDe('CONVERSATIONS');
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

const titulo = computed(() =>
  t('FUNCOES_EQUIPE.CONVERSAS.TITULO', {
    quem: quemFor(props.nome),
    nome: quemFor(props.nome, 'NOME'),
  })
);

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
// Pelo menos um alcance fica ligado (toggleExtra): o último diz por que não desliga, em vez de não responder.
const ultimoAlcance = chave => {
  const ligados = SUBESCOLHAS.filter(item => props.permissions.includes(item));
  return ligados.length === 1 && ligados[0] === chave;
};
const travaDaSubescolha = chave => {
  if (ultimoAlcance(chave)) return t('FUNCOES_EQUIPE.CONVERSAS.PELO_MENOS_UMA');
  return props.permissions.includes(chave)
    ? ''
    : textoDaTrava(motivoDaTrava(props.giver, chave));
};

// Voltar a "Atende as próprias" na mesma visita devolve os alcances com que a pergunta abriu, em vez do padrão.
const entrada = props.permissions;
const atualizar = permissions => emit('update:permissions', permissions);
const escolher = valor => {
  const novas = setLevel(conversas, valor, props.permissions);
  const voltaAsProprias =
    valor === CONVERSATION_LEVELS.LIMITED &&
    getLevel(conversas, entrada) === CONVERSATION_LEVELS.LIMITED;
  atualizar(
    voltaAsProprias
      ? [
          ...novas.filter(chave => !SUBESCOLHAS.includes(chave)),
          ...SUBESCOLHAS.filter(chave => entrada.includes(chave)),
        ]
      : novas
  );
};
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
    :titulo="titulo"
    :dica="$t('FUNCOES_EQUIPE.CONVERSAS.DICA')"
    @pronto="emit('pronto')"
  >
    <EscolhaDeNivel
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="titulo"
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
            :data-subescolha="chave"
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
