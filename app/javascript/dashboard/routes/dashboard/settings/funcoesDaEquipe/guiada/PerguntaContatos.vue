<script setup>
import { computed } from 'vue';
import {
  LEVELS,
  getLevel,
  levelOptions,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { travaDoNivel } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA } from '../motivoDaTrava';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import EscolhaDeNivel from './EscolhaDeNivel.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Contatos (#2308, especificação 5.B3): Não vê / Só olha / Pode mexer. "Campos extras" (ATTRIBUTES) mora aqui.
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  quem: { type: String, required: true },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, rotuloDoNivel } = useTextos();

const contatos = moduleByKey('CONTACTS');
const camposExtras = moduleByKey('ATTRIBUTES');
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

const atualizar = permissions => emit('update:permissions', permissions);
const escolher = valor =>
  atualizar(setLevel(contatos, valor, props.permissions));
</script>

<template>
  <PerguntaDaFuncao
    :titulo="$t('FUNCOES_EQUIPE.CONTATOS.TITULO', { quem })"
    @pronto="emit('pronto')"
  >
    <EscolhaDeNivel
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="$t('FUNCOES_EQUIPE.CONTATOS.TITULO', { quem })"
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
