<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { GRAVOU_EM_PARTE } from '../../fonte/gravarPessoa';
import { DA_EMPRESA, useCamposDaConta } from '../../ficha/useCamposDaConta';
import GavetaDaEmpresa from '../ficha/GavetaDaEmpresa.vue';

// #3078 — "Nova empresa" da aba Empresas (o "Criar empresa" da lista antiga,
// que pedia nome, site e descrição): a gaveta da empresa vazia, com tudo o que
// a ficha muda (foto, CNPJ, cidade e os campos personalizados da empresa;
// #3082 — os escolhidos para a ficha vêm logo depois do nome). Depois de criar,
// emite `criada` com a empresa (a página abre a ficha dela, o próximo passo
// de quem acabou de cadastrar).
// Se a empresa ficou gravada e só a foto (ou um campo) falhou, a gaveta fica
// aberta e guarda a `retomada` até completar: o próximo "Criar empresa" altera
// a empresa que já foi criada, sem criar outra. Fechar e abrir de novo não
// esquece: a gaveta volta com o nome dela e diz "Já criada: …". A frase que o
// servidor manda (site já usado por outra empresa; o CNPJ não é único) vira o
// aviso.
const props = defineProps({
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['criada']);

const { t } = useI18n();
const camposDaConta = useCamposDaConta({ de: DA_EMPRESA });
const aberta = ref(false);
const salvando = ref(false);
const retomada = ref(null);
const VAZIA = Object.freeze({});
const jaCriada = computed(() => retomada.value?.empresa ?? null);
const empresaDaGaveta = computed(() =>
  jaCriada.value ? { name: jaCriada.value.name } : VAZIA
);
const aviso = computed(() =>
  jaCriada.value
    ? t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.JA_CRIADA', {
        nome: jaCriada.value.name,
      })
    : ''
);

const abrir = () => {
  aberta.value = true;
};

const fraseDoServidor = falha => {
  const frase = falha?.response?.data?.message;
  return typeof frase === 'string' ? frase : '';
};

const aoFalhar = falha => {
  if (falha?.name === GRAVOU_EM_PARTE) {
    retomada.value = falha.retomada;
    useAlert(t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.EM_PARTE'));
    return;
  }
  useAlert(
    fraseDoServidor(falha) || t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.ERRO')
  );
};

const salvar = async pedido => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    const criada = await props.acoes.criarEmpresa(pedido, retomada.value);
    retomada.value = null;
    aberta.value = false;
    useAlert(
      t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.CRIADA', { nome: criada.name })
    );
    emit('criada', criada);
  } catch (falha) {
    aoFalhar(falha);
  } finally {
    salvando.value = false;
  }
};

defineExpose({ abrir });
</script>

<template>
  <GavetaDaEmpresa
    marca="gaveta-nova-empresa"
    :aberta="aberta"
    :empresa="empresaDaGaveta"
    :aviso="aviso"
    :salvando="salvando"
    :titulo="t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.TITULO')"
    :rotulo-salvar="t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.SALVAR')"
    :definicoes="camposDaConta.definicoes.value"
    :escolhidos="camposDaConta.escolhidos.value"
    :guardadas="camposDaConta.guardadas.value"
    @fechar="aberta = false"
    @salvar="salvar"
  />
</template>
