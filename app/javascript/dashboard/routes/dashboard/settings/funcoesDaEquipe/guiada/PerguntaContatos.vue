<script setup>
import { computed } from 'vue';
import {
  LEVELS,
  getLevel,
  levelOptions,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { areasDentroDe, travaDoNivel } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA } from '../motivoDaTrava';
import { useMemoria } from './memoriaDaConversa';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import EscolhaDeNivel from './EscolhaDeNivel.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Contatos (#2308, especificação 5.B3): Não vê / Só olha / Pode mexer. "Campos extras" (ATTRIBUTES) mora aqui. Voltar
// a um nível por onde passou devolve os ajustes de lá (memoriaDaConversa).
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  // O nome da função (a pronta antes do Confira); vazio, "Com esta função".
  nome: { type: String, default: '' },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, rotuloDoNivel, comAFuncao } = useTextos();
const memoria = useMemoria();

const contatos = moduleByKey('CONTACTS');
const [camposExtras] = areasDentroDe('CONTACTS');
const DICA = {
  [LEVELS.NONE]: 'NAO_VE',
  [LEVELS.VIEW]: 'SO_OLHA',
  [LEVELS.MANAGE]: 'PODE_MEXER',
};

const nivel = computed(() => getLevel(contatos, props.permissions));
const opcoes = computed(() =>
  levelOptions(contatos).map(valor => {
    const motivo =
      valor === nivel.value ? null : travaDoNivel(props.giver, contatos, valor);
    return {
      valor,
      titulo: rotuloDoNivel(contatos, valor),
      dica: t(`FUNCOES_EQUIPE.CONTATOS.DICA.${DICA[valor]}`),
      trava: motivo ? t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[motivo]}`) : '',
    };
  })
);

const titulo = computed(() =>
  t('FUNCOES_EQUIPE.CONTATOS.TITULO', { com: comAFuncao(props.nome) })
);

const atualizar = permissions => emit('update:permissions', permissions);
const escolher = valor =>
  atualizar(
    memoria.trocarNivel(contatos, {
      permissions: props.permissions,
      nivelar: chaves => setLevel(contatos, valor, chaves),
    })
  );
</script>

<template>
  <PerguntaDaFuncao :titulo="titulo" @pronto="emit('pronto')">
    <EscolhaDeNivel
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="titulo"
      @update:model-value="escolher"
    />
    <LinhaRecolhida
      icone="i-lucide-code"
      :titulo="$t('FUNCOES_EQUIPE.CONTATOS.MAIS')"
      :estado="rotuloDoNivel(camposExtras, getLevel(camposExtras, permissions))"
    >
      <AreaEmLinha
        :module="camposExtras"
        :permissions="permissions"
        :inicial="inicial"
        :giver="giver"
        @update:permissions="atualizar"
      />
    </LinhaRecolhida>
  </PerguntaDaFuncao>
</template>
