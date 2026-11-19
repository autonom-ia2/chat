<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { GRAVOU_EM_PARTE } from '../../fonte/gravarPessoa';
import { DA_EMPRESA, useCamposDaConta } from '../../ficha/useCamposDaConta';
import GavetaDaEmpresa from '../ficha/GavetaDaEmpresa.vue';

// #3078 — "Nova empresa" da aba Empresas (o "Criar empresa" da lista antiga,
// que pedia nome, site e descrição): a gaveta da empresa vazia, com tudo o que
// a ficha muda (foto, CNPJ, cidade e os campos personalizados da empresa, na
// ordem da conta: a lista não lê o configurador da ficha). Depois de criar,
// emite `criada` com a empresa (a página abre a ficha dela, o próximo passo
// de quem acabou de cadastrar).
// Se a empresa ficou gravada e só a foto (ou um campo) falhou, a gaveta fica
// aberta e guarda a `retomada`: o próximo "Salvar" altera a empresa que já foi
// criada, sem criar outra. A frase que o servidor manda (site ou CNPJ já
// usados por outra empresa) vira o aviso.
const props = defineProps({
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['criada']);

const { t } = useI18n();
const camposDaConta = useCamposDaConta({
  comConfiguracao: false,
  de: DA_EMPRESA,
});
const aberta = ref(false);
const salvando = ref(false);
const retomada = ref(null);
const VAZIA = Object.freeze({});

const abrir = () => {
  retomada.value = null;
  aberta.value = true;
};

const fraseDoServidor = falha => {
  const frase = falha?.response?.data?.message;
  return typeof frase === 'string' ? frase : '';
};

const aoFalhar = falha => {
  if (falha?.name === GRAVOU_EM_PARTE) {
    retomada.value = falha.retomada;
    useAlert(t('RELACIONAMENTOS_FICHA.GAVETA.SALVOU_EM_PARTE'));
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
    :empresa="VAZIA"
    :salvando="salvando"
    :titulo="t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.TITULO')"
    :rotulo-salvar="t('RELACIONAMENTOS.LISTA.NOVA_EMPRESA.SALVAR')"
    :definicoes="camposDaConta.definicoes.value"
    @fechar="aberta = false"
    @salvar="salvar"
  />
</template>
