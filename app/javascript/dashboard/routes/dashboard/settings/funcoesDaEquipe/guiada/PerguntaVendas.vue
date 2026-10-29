<script setup>
import { computed } from 'vue';
import { CRM_MOVE_CARDS_PERMISSION } from 'dashboard/constants/permissions';
import {
  LEVELS,
  isExtraLocked,
  moduleByKey,
  toggleExtra,
  visibleExtras,
} from '../../customRoles/permissionMatrix';
import { DONO_DAS_CHAVES, areasDentroDe } from '../areasDaFuncao';
import { soOlhaEMove } from '../fraseDaFuncao';
import { TEXTO_DA_TRAVA, motivoDaTrava } from '../motivoDaTrava';
import { nivelDeVendas } from '../nivelDeVendas';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import NivelDeVendas from './NivelDeVendas.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Vendas (#2308, especificação 5.B3): os quatro níveis e o "Mais" — arquivar, montar as colunas, os relatórios, os
// valores em R$ (de delegação) e, num bloco à parte com título, as áreas que andam junto: procurar clientes novos
// (PROSPECTING) e agenda (SCHEDULING).
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  nome: { type: String, default: '' },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, lista, comAFuncao } = useTextos();

const vendas = moduleByKey('CRM');
const areasDoMais = areasDentroDe('CRM');
const DO_MAIS = DONO_DAS_CHAVES.VENDAS_MAIS;

const temVendas = computed(
  () => nivelDeVendas(props.permissions) !== LEVELS.NONE
);
// Função antiga "Só olha" que move as vendas (gravada pela tela de antes): a linha aparece ligada para dar para
// desligar, e some quando desliga. Nada é gravado nem tirado sozinho.
const doMais = chave =>
  DO_MAIS.includes(chave) ||
  (chave === CRM_MOVE_CARDS_PERMISSION && soOlhaEMove(props.permissions));
const extras = computed(() =>
  visibleExtras(vendas, props.permissions).filter(doMais)
);

// Vem com "Cuida de tudo": fica ligada e diz por quê, em vez de um interruptor apagado.
const travaDoExtra = chave => {
  if (isExtraLocked(chave, props.permissions))
    return t('FUNCOES_EQUIPE.VENDAS.VEM_COM_TUDO');
  if (props.permissions.includes(chave)) return '';
  const motivo = motivoDaTrava(props.giver, chave);
  return motivo ? t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[motivo]}`) : '';
};

const ligados = computed(() =>
  extras.value.filter(chave => props.permissions.includes(chave))
);
const estadoDoMais = computed(() =>
  ligados.value.length
    ? lista(ligados.value.map(chave => t(`FUNCOES_EQUIPE.EXTRAS.${chave}`)))
    : t('FUNCOES_EQUIPE.VENDAS.MAIS_NADA')
);

const titulo = computed(() =>
  t('FUNCOES_EQUIPE.VENDAS.TITULO', { com: comAFuncao(props.nome) })
);

const atualizar = permissions => emit('update:permissions', permissions);
const alternar = chave =>
  atualizar(toggleExtra(vendas, chave, props.permissions));
</script>

<template>
  <PerguntaDaFuncao :titulo="titulo" @pronto="emit('pronto')">
    <NivelDeVendas
      :permissions="permissions"
      :inicial="inicial"
      :giver="giver"
      :nome="nome"
      :rotulo="titulo"
      @update:permissions="atualizar"
    />
    <LinhaRecolhida
      v-if="temVendas"
      icone="i-lucide-sliders-horizontal"
      :titulo="$t('FUNCOES_EQUIPE.VENDAS.MAIS')"
      :estado="estadoDoMais"
    >
      <div class="flex flex-col divide-y divide-n-weak">
        <InterruptorDaLinha
          v-for="chave in extras"
          :key="chave"
          :titulo="$t(`FUNCOES_EQUIPE.EXTRAS.${chave}`)"
          :ligado="permissions.includes(chave)"
          :trava="travaDoExtra(chave)"
          @alternar="alternar(chave)"
        />
      </div>
      <p
        data-mais-areas
        class="px-4 pt-4 pb-1 m-0 text-sm font-semibold border-t text-n-slate-11 border-n-weak"
      >
        {{ $t('FUNCOES_EQUIPE.VENDAS.MAIS_AREAS') }}
      </p>
      <div class="flex flex-col divide-y divide-n-weak">
        <AreaEmLinha
          v-for="area in areasDoMais"
          :key="area.key"
          :module="area"
          :permissions="permissions"
          :inicial="inicial"
          :giver="giver"
          @update:permissions="atualizar"
        />
      </div>
    </LinhaRecolhida>
  </PerguntaDaFuncao>
</template>
