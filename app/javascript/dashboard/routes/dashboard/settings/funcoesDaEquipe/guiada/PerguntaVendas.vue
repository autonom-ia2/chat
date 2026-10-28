<script setup>
import { computed } from 'vue';
import {
  LEVELS,
  isExtraLocked,
  moduleByKey,
  toggleExtra,
  visibleExtras,
} from '../../customRoles/permissionMatrix';
import { DONO_DAS_CHAVES } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA, motivoDaTrava } from '../motivoDaTrava';
import { nivelDeVendas } from '../nivelDeVendas';
import { useTextos } from './useTextos';
import AreaEmLinha from './AreaEmLinha.vue';
import InterruptorDaLinha from './InterruptorDaLinha.vue';
import LinhaRecolhida from './LinhaRecolhida.vue';
import NivelDeVendas from './NivelDeVendas.vue';
import PerguntaDaFuncao from './PerguntaDaFuncao.vue';

// Vendas (#2308, especificação 5.B3): os quatro níveis e o "Mais" — arquivar, montar as colunas, os relatórios, os
// valores em R$ (de delegação), procurar clientes novos (PROSPECTING) e agenda (SCHEDULING).
const props = defineProps({
  permissions: { type: Array, required: true },
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  quem: { type: String, required: true },
});

const emit = defineEmits(['update:permissions', 'pronto']);
const { t, lista } = useTextos();

const vendas = moduleByKey('CRM');
const areasDoMais = [moduleByKey('PROSPECTING'), moduleByKey('SCHEDULING')];
const DO_MAIS = DONO_DAS_CHAVES.VENDAS_MAIS;

const temVendas = computed(
  () => nivelDeVendas(props.permissions) !== LEVELS.NONE
);
const extras = computed(() =>
  visibleExtras(vendas, props.permissions).filter(chave =>
    DO_MAIS.includes(chave)
  )
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

const atualizar = permissions => emit('update:permissions', permissions);
const alternar = chave =>
  atualizar(toggleExtra(vendas, chave, props.permissions));
</script>

<template>
  <PerguntaDaFuncao
    :titulo="$t('FUNCOES_EQUIPE.VENDAS.TITULO', { quem })"
    @pronto="emit('pronto')"
  >
    <NivelDeVendas
      :permissions="permissions"
      :giver="giver"
      :quem="quem"
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
