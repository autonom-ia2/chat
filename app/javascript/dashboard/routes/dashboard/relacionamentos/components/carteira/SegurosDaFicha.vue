<script setup>
import { onMounted, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { pecaPedida } from '../../fonte/modoCarteira';
import { destinoDoCard } from '../../carteira/cardNoCrm';
import { useApoliceNaUrl } from '../../carteira/useApoliceNaUrl';
import {
  ESTADOS_DOS_SEGUROS as ESTADOS,
  useSegurosDe,
} from '../../carteira/useSegurosDe';
import { useVerPdf } from '../../carteira/useVerPdf';
import DialogoAnexarPdf from './DialogoAnexarPdf.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import SecaoSeguros from './SecaoSeguros.vue';

// #2897 — os seguros dentro de uma ficha (pessoa ou empresa): o bloco, a gaveta
// do seguro (o endereço ganha `?apolice=<id>`) e o diálogo de guardar o PDF
// direto da linha. A ficha só põe esta peça no lugar; ela mesma fala com a
// fonte da carteira. `demo` é o estado da demonstração que a ficha leu do
// endereço (nulo fora dela). Quem não pode ver os seguros não vê o bloco; quem
// só pode ver a pessoa (`podeEditar` falso) lê e abre o PDF, sem mudar nada.
const props = defineProps({
  donoId: { type: Number, required: true },
  daEmpresa: { type: Boolean, default: false },
  demo: { type: String, default: null },
  podeEditar: { type: Boolean, default: false },
  podeExportar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['abrirSegurado']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const fonte = carteiraFonte({
  demo: props.demo,
  peca: pecaPedida(route.query),
});
const { apolice, abrir, fechar } = useApoliceNaUrl();
// #2898 — "Abrir no CRM" da renovação de um seguro.
const abrirCard = cardId => router.push(destinoDoCard(cardId, fonte.usaDemo));
const verPdfDe = useVerPdf(fonte);
const dialogoDoPdf = useTemplateRef('dialogoDoPdf');

const lista = useSegurosDe(() =>
  props.daEmpresa ? fonte.daEmpresa(props.donoId) : fonte.daPessoa(props.donoId)
);

const verPdf = async seguro => {
  const naoAbriu = await verPdfDe(seguro.id);
  if (!naoAbriu) return;
  useAlert(naoAbriu);
  lista.atualizar();
};
const aoGuardarPdf = () => {
  useAlert(t('RELACIONAMENTOS_CARTEIRA.GAVETA.AVISOS.PDF_GUARDADO'));
  lista.atualizar();
};

watch(() => props.donoId, lista.carregar);
onMounted(lista.carregar);
</script>

<template>
  <SecaoSeguros
    v-if="lista.estado.value !== ESTADOS.ESCONDIDO"
    :seguros="lista.seguros.value"
    :estado="lista.estado.value"
    :da-empresa="daEmpresa"
    :pode-guardar="podeEditar"
    :agora="agora"
    @abrir="abrir($event.id)"
    @pdf="verPdf"
    @guardar="dialogoDoPdf?.abrir($event)"
    @tentar="lista.carregar"
  />
  <GavetaDoSeguro
    :apolice-id="apolice"
    :fonte="fonte"
    :pode-editar="podeEditar"
    :pode-exportar="podeExportar"
    :agora="agora"
    @fechar="fechar"
    @mudou="lista.atualizar"
    @abrir-segurado="emit('abrirSegurado', $event)"
    @abrir-card="abrirCard"
  />
  <DialogoAnexarPdf
    v-if="podeEditar"
    ref="dialogoDoPdf"
    :fonte="fonte"
    @guardado="aoGuardarPdf"
  />
</template>
