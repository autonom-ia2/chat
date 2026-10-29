<script setup>
import { computed, ref } from 'vue';
import { moduleByKey } from '../../customRoles/permissionMatrix';
import { travaDoNivel } from '../areasDaFuncao';
import { TEXTO_DA_TRAVA } from '../motivoDaTrava';
import {
  CRM_ADMIN,
  NIVEIS_DE_VENDAS,
  TUDO,
  escolherNivelDeVendas,
  nivelDeVendas,
  travaDoTudo,
} from '../nivelDeVendas';
import { useMemoria } from './memoriaDaConversa';
import { useTextos } from './useTextos';
import DialogoDaCasa from './DialogoDaCasa.vue';
import EscolhaDeNivel from './EscolhaDeNivel.vue';

// Os quatro níveis de Vendas (#2308, especificação 5.B3 e 7.4). "Cuida de tudo" pede confirmação (5.F) e, para
// quem não é administrador nem tem grant_above_own, fica tracejado com "Só o administrador dá isto.". O aviso não
// fala em metas nem em R$ (decisão 14A). O "antes do 4º nível" fica na memória da conversa, não aqui: a pergunta é
// desmontada no "Pronto", e sair de "Cuida de tudo" numa visita seguinte ainda devolve o que era. Entre os outros
// três, voltar a um nível por onde passou devolve os ajustes de lá; entrar e sair do 4º esquece o que estava guardado
// (revisão do #2308, rodada 4).
const props = defineProps({
  permissions: { type: Array, required: true },
  // A função quando abriu: com crm_admin, sair do 4º nível tira as seis (não dá para saber o que era dela).
  inicial: { type: Array, required: true },
  giver: { type: Object, required: true },
  nome: { type: String, default: '' },
  rotulo: { type: String, required: true },
});

const emit = defineEmits(['update:permissions']);
const { t, comAFuncao } = useTextos();
const memoria = useMemoria();

const vendas = moduleByKey('CRM');
const OPCAO = {
  none: 'NAO_VE',
  view: 'SO_OLHA',
  manage: 'PODE_MEXER',
  [TUDO]: 'TUDO',
};
const dialogo = ref(null);

const nivel = computed(() => nivelDeVendas(props.permissions));
const motivoDe = valor =>
  valor === TUDO
    ? travaDoTudo(props.giver)
    : travaDoNivel(props.giver, vendas, valor);

const opcoes = computed(() =>
  NIVEIS_DE_VENDAS.map(valor => {
    const motivo = valor === nivel.value ? null : motivoDe(valor);
    return {
      valor,
      titulo: t(`FUNCOES_EQUIPE.VENDAS.${OPCAO[valor]}.TITULO`),
      dica: t(`FUNCOES_EQUIPE.VENDAS.${OPCAO[valor]}.DICA`),
      trava: motivo ? t(`FUNCOES_EQUIPE.TRAVA.${TEXTO_DA_TRAVA[motivo]}`) : '',
      confirma: valor === TUDO,
    };
  })
);

// O que a função tinha ao entrar no 4º nível; sem isso, vale a de quando abriu (se não abriu com crm_admin).
const antes = () =>
  memoria.antesDoTudo() ||
  (props.inicial.includes(CRM_ADMIN) ? null : props.inicial);

const nivelar = valor => chaves =>
  escolherNivelDeVendas(valor, chaves, antes());

const aplicar = valor => {
  if (valor === TUDO && nivel.value !== TUDO)
    memoria.guardarAntesDoTudo(props.permissions);
  const comMemoria = ![valor, nivel.value].includes(TUDO);
  if (!comMemoria) memoria.esquecer(vendas.key);
  emit(
    'update:permissions',
    comMemoria
      ? memoria.trocarNivel(vendas, {
          permissions: props.permissions,
          nivelar: nivelar(valor),
        })
      : nivelar(valor)(props.permissions)
  );
};

const escolher = valor => {
  if (valor === TUDO) dialogo.value?.abrir();
  else aplicar(valor);
};
</script>

<template>
  <div>
    <EscolhaDeNivel
      :model-value="nivel"
      :opcoes="opcoes"
      :rotulo="rotulo"
      @update:model-value="escolher"
    />
    <DialogoDaCasa
      ref="dialogo"
      :titulo="
        $t('FUNCOES_EQUIPE.VENDAS.AVISO_TUDO.TITULO', {
          com: comAFuncao(nome),
        })
      "
      :texto="$t('FUNCOES_EQUIPE.VENDAS.AVISO_TUDO.TEXTO')"
      :risco="$t('FUNCOES_EQUIPE.VENDAS.AVISO_TUDO.RISCO')"
      :seguro="$t('FUNCOES_EQUIPE.GUIADA.AGORA_NAO')"
      :acao="$t('FUNCOES_EQUIPE.VENDAS.AVISO_TUDO.LIGAR')"
      @acao="aplicar(TUDO)"
    />
  </div>
</template>
