<script setup>
import { onMounted, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { pecaPedida } from '../../fonte/modoCarteira';
import { estadoDemo } from '../../fonte/modoDemo';
import { useApoliceNaUrl } from '../../carteira/useApoliceNaUrl';
import { useSegurosDe } from '../../carteira/useSegurosDe';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import DialogoAnexarPdf from './DialogoAnexarPdf.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import SecaoSeguros from './SecaoSeguros.vue';

// #2897 — os seguros dentro de uma ficha (pessoa ou empresa): o bloco, a
// gaveta do seguro (o endereço ganha `?apolice=<id>`) e o diálogo de anexar o
// PDF direto da linha. A ficha só põe esta peça no lugar; ela mesma fala com a
// fonte da carteira. `desde` avisa a ficha quando o seguro mais antigo começou
// (o "Cliente desde" do cabeçalho).
const props = defineProps({
  donoId: { type: Number, required: true },
  daEmpresa: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrirSegurado', 'desde']);

const { t } = useI18n();
const route = useRoute();
const textos = useTextosDoSeguro();
const fonte = carteiraFonte({
  demo: estadoDemo(),
  peca: pecaPedida(route.query),
});
const { apolice, abrir, fechar } = useApoliceNaUrl();
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');

const lista = useSegurosDe(() =>
  props.daEmpresa ? fonte.daEmpresa(props.donoId) : fonte.daPessoa(props.donoId)
);

const verPdf = seguro =>
  useAlert(
    t('RELACIONAMENTOS_CARTEIRA.FICHA.ABRINDO_PDF', {
      tipo: textos.tipo(seguro),
    })
  );
const aoGuardarPdf = ({ apoliceNova }) => {
  useAlert(
    t(
      `RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.${apoliceNova ? 'APOLICE_NOVA' : 'PDF_GUARDADO'}`
    )
  );
  lista.atualizar();
};

// O "Cliente desde" do cabeçalho: o começo do seguro mais antigo da carteira.
watch(lista.seguros, seguros => {
  const comecos = seguros.filter(s => !s.deFora).map(s => s.comeca);
  emit('desde', comecos.length ? Math.min(...comecos) : null);
});
watch(() => props.donoId, lista.carregar);
onMounted(lista.carregar);
</script>

<template>
  <SecaoSeguros
    :seguros="lista.seguros.value"
    :estado="lista.estado.value"
    :da-empresa="daEmpresa"
    :agora="agora"
    @abrir="abrir($event.id)"
    @pdf="verPdf"
    @anexar="dialogoDoPdf?.abrir($event)"
    @tentar="lista.carregar"
  />
  <GavetaDoSeguro
    :apolice-id="apolice"
    :fonte="fonte"
    :agora="agora"
    @fechar="fechar"
    @mudou="lista.atualizar"
    @abrir-segurado="emit('abrirSegurado', $event)"
  />
  <DialogoAnexarPdf
    ref="dialogoDoPdf"
    :fonte="fonte"
    @guardado="aoGuardarPdf"
  />
</template>
