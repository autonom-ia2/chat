<script setup>
// Enviar pela CONVERSA um modelo de produto (um, vários ou carrossel de
// produtos) ou um carrossel de fotos (#1716, épico #1320). Uma ação por tela:
//   produtos → a gaveta de produtos da Campanha (GavetaDeProdutos, a mesma) →
//              "Confira e envie" com a ordem, os espaços do texto e a prévia;
//   fotos    → "Cartão 1 de 3" (foto + espaços), um por vez, com a prévia ao
//              lado → "Confira e envie" com todos os cartões.
// Ao enviar, o catálogo é relido: produto que acabou fica marcado e não sai.
// A janela é o Dialog nativo (como o "+" da conversa, #1702). A gaveta não cabe
// por cima dele (camada do navegador): a janela fecha enquanto a gaveta está
// aberta e volta quando a pessoa escolhe.
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { ABRIR_MODELOS_DO_WHATSAPP } from 'dashboard/components-next/conversa-canal/pele';
import Dialog from 'next/dialog/Dialog.vue';
import Button from 'next/button/Button.vue';
import GavetaDeProdutos from '../ponte/GavetaDeProdutos.vue';
import api from '../api/modelosWhatsapp';
import { LIMITES_DE_PRODUTOS } from '../helpers/produtosNaCampanha';
import EtapaDoCartao from './EtapaDoCartao.vue';
import ProdutosEscolhidos from './ProdutosEscolhidos.vue';
import CartoesConferidos from './CartoesConferidos.vue';
import CamposDaMensagem from './CamposDaMensagem.vue';
import AvisoDoEnvio from './AvisoDoEnvio.vue';
import SemCatalogo from './SemCatalogo.vue';
import PreviaDoModeloNaConversa from './PreviaDoModeloNaConversa.vue';
import { lerPerfilDoModelo } from './perfilDoModelo';
import { useCompletaNaConversa } from './useCompletaNaConversa';
import {
  camposDoContato,
  camposDoTexto,
  cartaoPronto,
  cartoesDoModelo,
  comEstoqueRelido,
  componenteDe,
  faltaNoCorpo,
  levaProdutos,
  montarEnvio,
  moverProduto,
  tipoNaConversa,
} from './modeloNaConversa';

const props = defineProps({
  caixa: { type: [Number, String], required: true },
});
const emit = defineEmits(['enviar']);

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA';
const conversa = useMapGetter('getSelectedChat');
const { podeSubirFoto } = useCompletaNaConversa(computed(() => props.caixa));

const dialogo = ref(null);
const template = ref(null);
const tipo = ref('');
// 'semCatalogo' | 'cartao' | 'confira'
const etapa = ref('');
const gaveta = ref(false);
const produtos = ref([]);
const cartoes = ref({});
const corpo = ref({});
const indice = ref(0);
const aviso = ref('');
const motivoSemCatalogo = ref('');
const enviando = ref(false);
const galeria = ref([]);
const galeriaFalhou = ref(false);
// Miniaturas das fotos do computador, soltas ao fechar.
let miniaturas = [];
// A janela fecha para a gaveta abrir: esse fechamento não desfaz nada. O
// Dialog avisa o fechamento duas vezes (no close() e no evento do navegador),
// então a marca só sai quando a janela abre de novo.
let trocandoDeTela = false;

const pedido = computed(() =>
  levaProdutos(tipo.value)
    ? { tipo: tipo.value, ...LIMITES_DE_PRODUTOS[tipo.value] }
    : null
);
const modeloDosCartoes = computed(() =>
  template.value ? cartoesDoModelo(template.value) : []
);
const cartaoDaVez = computed(() => modeloDosCartoes.value[indice.value]);
const corpoDoModelo = computed(() =>
  template.value ? componenteDe(template.value, 'BODY') : null
);
const camposDoCorpo = computed(() => camposDoTexto(corpoDoModelo.value?.text));

const limpar = () => {
  miniaturas.forEach(url => URL.revokeObjectURL(url));
  miniaturas = [];
  etapa.value = '';
  gaveta.value = false;
  produtos.value = [];
  cartoes.value = {};
  corpo.value = {};
  indice.value = 0;
  aviso.value = '';
  motivoSemCatalogo.value = '';
  enviando.value = false;
  galeria.value = [];
  galeriaFalhou.value = false;
};

const mostrarJanela = async () => {
  await nextTick();
  trocandoDeTela = false;
  dialogo.value?.open();
};
const esconderJanela = () => {
  trocandoDeTela = true;
  dialogo.value?.close();
};
const aoFecharJanela = () => {
  if (!trocandoDeTela) limpar();
};

const semCatalogo = motivo => {
  gaveta.value = false;
  motivoSemCatalogo.value = motivo;
  etapa.value = 'semCatalogo';
  mostrarJanela();
};

// O catálogo da caixa: null sem catálogo (ou flag desligada); erro da Meta
// vira o motivo na tela.
const lerCatalogo = () =>
  api
    .obterCatalogo(props.caixa)
    .then(catalogo => ({ catalogo }))
    .catch(erro => ({ erro }));

const abrir = async modelo => {
  trocandoDeTela = false;
  limpar();
  template.value = modelo;
  tipo.value = tipoNaConversa(modelo);
  const [perfil, leitura] = await Promise.all([
    lerPerfilDoModelo(props.caixa, modelo),
    pedido.value ? lerCatalogo() : Promise.resolve(null),
  ]);
  const contato = conversa.value?.meta?.sender;
  corpo.value = camposDoContato(modelo, perfil.campos, contato);
  galeria.value = perfil.galeria;
  galeriaFalhou.value = perfil.falhou;
  if (tipo.value === 'cartoes') {
    etapa.value = 'cartao';
    mostrarJanela();
    return;
  }
  if (!leitura?.catalogo) {
    semCatalogo(leitura?.erro?.mensagem || '');
    return;
  }
  gaveta.value = true;
};

const abrirGaveta = () => {
  esconderJanela();
  gaveta.value = true;
};
const usarProdutos = lista => {
  produtos.value = lista;
  aviso.value = '';
  gaveta.value = false;
  etapa.value = 'confira';
  mostrarJanela();
};
// Fechou a gaveta sem escolher: na primeira vez, desiste; depois, volta à conferência.
const fecharGaveta = () => {
  gaveta.value = false;
  if (produtos.value.length) mostrarJanela();
  else limpar();
};
const mover = (posicao, passo) => {
  produtos.value = moverProduto(produtos.value, posicao, passo);
};

// Pelo cartão que mandou (a foto do computador pode chegar depois de a pessoa
// passar ao próximo cartão).
const mudarCartao = (posicao, valor) => {
  cartoes.value = { ...cartoes.value, [posicao]: valor };
};
const guardarMiniatura = url => {
  miniaturas = [...miniaturas, url];
};
const cartaoDaVezPronto = computed(
  () =>
    Boolean(cartaoDaVez.value) &&
    cartaoPronto(cartaoDaVez.value, cartoes.value[indice.value])
);
const ultimoCartao = computed(
  () => indice.value === modeloDosCartoes.value.length - 1
);
const avancarCartao = () => {
  if (!cartaoDaVezPronto.value) return;
  if (ultimoCartao.value) etapa.value = 'confira';
  else indice.value += 1;
};
const alterarCartao = posicao => {
  indice.value = posicao;
  etapa.value = 'cartao';
};

const voltar = () => {
  if (etapa.value === 'confira' && tipo.value === 'cartoes') {
    etapa.value = 'cartao';
    return;
  }
  if (etapa.value === 'cartao' && indice.value > 0) {
    indice.value -= 1;
    return;
  }
  dialogo.value?.close();
  emitter.emit(ABRIR_MODELOS_DO_WHATSAPP);
};

const temEsgotado = computed(() =>
  produtos.value.some(produto => !produto.disponivel)
);
const podeEnviar = computed(
  () =>
    Boolean(template.value) &&
    !faltaNoCorpo(template.value, corpo.value).length &&
    !temEsgotado.value &&
    !enviando.value
);

// Relê os escolhidos no catálogo: o que acabou fica marcado e o envio espera a troca.
const conferirEstoque = async () => {
  const relidos = await api.conferirProdutos(
    props.caixa,
    produtos.value.map(produto => produto.id)
  );
  produtos.value = comEstoqueRelido(produtos.value, relidos);
  const acabaram = produtos.value.filter(produto => !produto.disponivel);
  if (!acabaram.length) return true;
  aviso.value = t(
    `${NS}.ESGOTADO`,
    { nome: acabaram.map(produto => produto.nome).join(', ') },
    acabaram.length
  );
  return false;
};

const despachar = () => {
  emit(
    'enviar',
    montarEnvio({
      template: template.value,
      tipo: tipo.value,
      corpo: corpo.value,
      produtos: produtos.value,
      cartoes: cartoes.value,
    })
  );
  dialogo.value?.close();
};

// Só pelo botão Enviar: Enter num campo não envia ao cliente.
const enviar = async () => {
  if (etapa.value !== 'confira' || !podeEnviar.value) return;
  enviando.value = true;
  aviso.value = '';
  try {
    if (pedido.value && !(await conferirEstoque())) return;
    despachar();
  } catch (erro) {
    if (erro?.codigo === 'catalog_missing') semCatalogo('');
    else aviso.value = erro?.mensagem || t(`${NS}.ERRO_GERAL`);
  } finally {
    enviando.value = false;
  }
};

const titulo = computed(() => {
  if (etapa.value === 'semCatalogo') return t(`${NS}.SEM_CATALOGO.TITULO`);
  if (etapa.value === 'cartao') {
    return t(`${NS}.CARTAO.TITULO`, {
      n: indice.value + 1,
      total: modeloDosCartoes.value.length,
    });
  }
  return etapa.value ? t(`${NS}.CONFIRA.TITULO`) : '';
});
const ajuda = computed(() => {
  if (etapa.value === 'semCatalogo') return t(`${NS}.SEM_CATALOGO.AJUDA`);
  if (etapa.value === 'cartao') return t(`${NS}.CARTAO.AJUDA`);
  return etapa.value ? t(`${NS}.CONFIRA.AJUDA.${tipo.value}`) : '';
});
const largura = computed(() =>
  ['cartoes', 'carrossel'].includes(tipo.value) ? '3xl' : '2xl'
);

defineExpose({ abrir });
</script>

<template>
  <div class="contents">
    <Dialog
      ref="dialogo"
      :title="titulo"
      :description="ajuda"
      :width="largura"
      position="top"
      overflow-y-auto
      @close="aoFecharJanela"
    >
      <SemCatalogo v-if="etapa === 'semCatalogo'" :motivo="motivoSemCatalogo" />

      <div
        v-else-if="etapa"
        class="grid gap-6"
        :class="
          largura === '3xl'
            ? 'md:grid-cols-[minmax(0,1fr)_22rem]'
            : 'md:grid-cols-[minmax(0,1fr)_17rem]'
        "
        :data-etapa="etapa"
      >
        <div class="flex flex-col min-w-0 gap-5">
          <EtapaDoCartao
            v-if="etapa === 'cartao' && cartaoDaVez"
            :key="indice"
            :caixa="caixa"
            :cartao="cartaoDaVez"
            :valor="cartoes[indice] || {}"
            :galeria="galeria"
            :pode-subir="podeSubirFoto"
            :galeria-falhou="galeriaFalhou"
            @update="mudarCartao"
            @miniatura="guardarMiniatura"
          />

          <template v-else>
            <ProdutosEscolhidos
              v-if="pedido"
              :tipo="tipo"
              :produtos="produtos"
              @mover="mover"
              @trocar="abrirGaveta"
            />
            <CartoesConferidos
              v-if="tipo === 'cartoes'"
              :cartoes="modeloDosCartoes"
              :valores="cartoes"
              @alterar="alterarCartao"
            />
            <CamposDaMensagem
              v-if="camposDoCorpo.length"
              :corpo="corpoDoModelo"
              :campos="camposDoCorpo"
              :valores="corpo"
              @update="valores => (corpo = valores)"
            />
          </template>

          <AvisoDoEnvio v-if="aviso" :texto="aviso" />
        </div>

        <div class="flex flex-col min-w-0 gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`${NS}.PREVIA.TITULO`) }}
          </span>
          <PreviaDoModeloNaConversa
            :template="template"
            :tipo="tipo"
            :corpo="corpo"
            :produtos="produtos"
            :cartoes="cartoes"
            :cartao-atual="etapa === 'cartao' ? indice : -1"
          />
        </div>
      </div>

      <template #footer>
        <div class="flex flex-wrap items-center justify-end w-full gap-3">
          <Button
            type="button"
            variant="faded"
            color="slate"
            class="min-h-11"
            :label="
              etapa === 'semCatalogo'
                ? t(`${NS}.SEM_CATALOGO.OUTRO_MODELO`)
                : t(`${NS}.VOLTAR`)
            "
            data-voltar
            @click="voltar"
          />
          <Button
            v-if="etapa === 'cartao'"
            type="button"
            color="teal"
            class="min-h-11"
            :disabled="!cartaoDaVezPronto"
            :label="
              ultimoCartao
                ? t(`${NS}.CARTAO.REVISAR`)
                : t(`${NS}.CARTAO.PROXIMO`)
            "
            data-proximo-cartao
            @click="avancarCartao"
          />
          <Button
            v-else-if="etapa === 'confira'"
            type="button"
            color="teal"
            class="min-h-11"
            icon="i-ph-paper-plane-right-fill"
            :is-loading="enviando"
            :disabled="!podeEnviar"
            :label="t(`${NS}.ENVIAR`)"
            data-enviar-modelo
            @click="enviar"
          />
        </div>
      </template>
    </Dialog>

    <GavetaDeProdutos
      v-if="gaveta && pedido"
      :caixa="caixa"
      :pedido="pedido"
      :escolhidos="produtos.filter(produto => produto.disponivel)"
      @usar="usarProdutos"
      @fechar="fecharGaveta"
    />
  </div>
</template>
