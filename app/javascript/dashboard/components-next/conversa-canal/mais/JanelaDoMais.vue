<script setup>
// Janela de cada item do "+" (#1702): poucos campos, a prévia do balão ao lado e um
// botão Enviar. A janela só fecha quando o servidor aceitou; se recusar, o motivo
// aparece aqui e o atendente corrige sem redigitar.
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import getUuid from 'widget/helpers/uuid';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import ContactsAPI from 'dashboard/api/contacts';
import Dialog from 'next/dialog/Dialog.vue';
import ChoiceSelect from 'next/choice-select/ChoiceSelect.vue';
import CampoDeBusca from './CampoDeBusca.vue';
import CampoDeTelefone from './CampoDeTelefone.vue';
import Input from 'next/input/Input.vue';
import TextArea from 'next/textarea/TextArea.vue';
import Button from 'next/button/Button.vue';
import Checkbox from 'next/checkbox/Checkbox.vue';
import PreviaDoMais from './PreviaDoMais.vue';
import {
  LIMITES,
  montarBotaoDeLink,
  montarContato,
  montarEnquete,
  montarFormulario,
  montarLocalizacao,
  montarOpcoes,
  montarPedidoDeLocalizacao,
  viraLista,
} from './montarMensagem';

const props = defineProps({
  // Caixa da conversa: o formulário só existe no WhatsApp oficial.
  inboxId: { type: Number, default: null },
  // WAHA e número reserva: o cliente recebe a versão em texto; a prévia mostra isso.
  viraTexto: { type: Boolean, default: false },
  // A enquete tem regra própria (enqueteNoMais.js): nativa só onde a conversa diz.
  enqueteEmTexto: { type: Boolean, default: false },
  // pedido → Promise; rejeita com a resposta do servidor quando ele recusa.
  enviar: { type: Function, required: true },
});

const emit = defineEmits(['fechou']);

const { t } = useI18n();
const dialogo = ref(null);
const tipo = ref('');
const erros = ref({});
// Cada abertura tem um número: resposta que chega depois de fechar ou reabrir é ignorada.
const abertura = ref(0);

const MONTADORES = {
  botaoDeLink: montarBotaoDeLink,
  opcoes: montarOpcoes,
  localizacao: montarLocalizacao,
  pedidoDeLocalizacao: montarPedidoDeLocalizacao,
  contato: montarContato,
  enquete: montarEnquete,
};

const camposVazios = () => ({
  mensagem: '',
  nomeDoBotao: '',
  endereco: '',
  opcoes: ['', '', ''],
  nomeDaLista: '',
  cabecalho: '',
  coordenadas: '',
  nome: '',
  telefone: '',
  formulario: '',
  textoDoBotao: '',
  pergunta: '',
  variasRespostas: false,
});
const campos = reactive(camposVazios());

const fechar = () => dialogo.value?.close();

const aoFechar = () => {
  abertura.value += 1;
  tipo.value = '';
  emit('fechou');
};

const chave = computed(
  () =>
    ({
      botaoDeLink: 'BOTAO_DE_LINK',
      opcoes: 'OPCOES',
      localizacao: 'LOCALIZACAO',
      pedidoDeLocalizacao: 'PEDIDO_DE_LOCALIZACAO',
      contato: 'CONTATO',
      formulario: 'FORMULARIO',
      enquete: 'ENQUETE',
    })[tipo.value]
);
const rotulo = campo => t(`CONVERSA_CANAL.JANELA.${chave.value}.${campo}`);
// Se o cliente recebe em texto, a prévia mostra esse texto.
const emTexto = computed(() =>
  tipo.value === 'enquete' ? props.enqueteEmTexto : props.viraTexto
);
// No WAHA o cliente recebe em texto: a ajuda não promete botão nem lista.
const ajuda = computed(() => {
  if (!tipo.value) return '';
  if (tipo.value === 'enquete' && emTexto.value) return rotulo('AJUDA_TEXTO');
  if (emTexto.value) return t('CONVERSA_CANAL.JANELA.AJUDA_TEXTO');
  return rotulo('AJUDA');
});
const titulo = computed(() =>
  tipo.value ? t(`CONVERSA_CANAL.JANELA.${chave.value}.TITULO`) : ''
);
const erroDe = campo =>
  erros.value[campo]
    ? t(`CONVERSA_CANAL.JANELA.ERROS.${erros.value[campo]}`)
    : '';

const ehLista = computed(() => viraLista(campos.opcoes));
const podeMaisOpcao = computed(
  () =>
    campos.opcoes.length <
    (tipo.value === 'enquete' ? LIMITES.opcoesDaEnquete : LIMITES.opcoes)
);

const falha = ref('');
const enviando = ref(false);
const motivo = error =>
  error?.response?.data?.error || t('CONVERSA_CANAL.JANELA.ERRO_GERAL');

// Localização: o endereço escolhido traz nome, endereço e o ponto no mapa. Uma sessão
// do Google por janela aberta (as sugestões e o detalhe saem cobrados como uma busca).
const verCoordenadas = ref(false);
const sessao = ref('');
const buscandoLugar = ref(0);
const buscarLugar = async texto => {
  const { data } = await ConversaCanalAPI.sugerirLugares(texto, sessao.value);
  return data.payload.map(lugar => ({
    id: lugar.place_id,
    titulo: lugar.text,
  }));
};
const escolherLugar = async ({ id }) => {
  buscandoLugar.value += 1;
  const pedido = buscandoLugar.value;
  const daVez = abertura.value;
  campos.coordenadas = '';
  falha.value = '';
  try {
    const { data } = await ConversaCanalAPI.lugar(id, sessao.value);
    if (pedido !== buscandoLugar.value || daVez !== abertura.value) return;
    campos.nome = data.nome || '';
    campos.endereco = data.endereco || '';
    campos.coordenadas = `${data.latitude}, ${data.longitude}`;
  } catch (error) {
    if (pedido === buscandoLugar.value && daVez === abertura.value) {
      falha.value = motivo(error);
    }
  }
};

// Contato: busca nos contatos da conta; só servem os que têm telefone.
const buscarContato = async texto => {
  const { data } = await ContactsAPI.search(texto);
  return (data.payload || [])
    .filter(contato => contato.phone_number)
    .slice(0, 8)
    .map(contato => ({
      id: contato.id,
      titulo: contato.name || contato.phone_number,
      detalhe: contato.phone_number,
    }));
};
const escolherContato = contato => {
  campos.telefone = contato.detalhe;
};

// Formulário: os aprovados da caixa, lidos na Meta quando a janela abre.
const formularios = ref([]);
const carregarFormularios = async () => {
  const daVez = abertura.value;
  formularios.value = [];
  try {
    const { data } = await ConversaCanalAPI.formularios(props.inboxId);
    if (daVez !== abertura.value) return;
    formularios.value = data.payload.map(formulario => ({
      value: formulario.id,
      label: formulario.nome,
    }));
    if (!formularios.value.length) {
      falha.value = t('CONVERSA_CANAL.JANELA.FORMULARIO.NENHUM');
    }
  } catch (error) {
    if (daVez === abertura.value) falha.value = motivo(error);
  }
};
const nomeDoFormulario = computed(
  () =>
    formularios.value.find(formulario => formulario.value === campos.formulario)
      ?.label || ''
);

// O formulário pede a primeira tela ao servidor antes de montar o envio.
const montarDoFormulario = async () => {
  const conferido = montarFormulario({ ...campos }, { tela: '-', token: '-' });
  if (conferido.erros) return conferido;
  const { data } = await ConversaCanalAPI.primeiraTela(
    props.inboxId,
    campos.formulario
  );
  return montarFormulario(
    { ...campos, nomeDoFormulario: nomeDoFormulario.value },
    { tela: data.tela, token: `${getUuid()}${Date.now().toString(36)}` }
  );
};

const enviar = async () => {
  if (enviando.value || !tipo.value) return;
  const daVez = abertura.value;
  enviando.value = true;
  falha.value = '';
  try {
    const { erros: faltam, pedido } =
      tipo.value === 'formulario'
        ? await montarDoFormulario()
        : MONTADORES[tipo.value]({ ...campos });
    if (daVez !== abertura.value) return;
    erros.value = faltam || {};
    if (faltam) return;
    await props.enviar(pedido);
    if (daVez === abertura.value) fechar();
  } catch (error) {
    if (daVez === abertura.value) falha.value = motivo(error);
  } finally {
    if (daVez === abertura.value) enviando.value = false;
  }
};

const abrir = novoTipo => {
  abertura.value += 1;
  Object.assign(campos, camposVazios());
  if (novoTipo === 'pedidoDeLocalizacao') {
    campos.mensagem = t('CONVERSA_CANAL.JANELA.PEDIDO_DE_LOCALIZACAO.PADRAO');
  }
  if (novoTipo === 'opcoes') {
    campos.nomeDaLista = t('CONVERSA_CANAL.JANELA.OPCOES.LISTA_PADRAO');
  }
  verCoordenadas.value = false;
  sessao.value = getUuid();
  falha.value = '';
  erros.value = {};
  enviando.value = false;
  tipo.value = novoTipo;
  if (novoTipo === 'formulario') {
    campos.textoDoBotao = t('CONVERSA_CANAL.JANELA.FORMULARIO.BOTAO_PADRAO');
    carregarFormularios();
  }
  dialogo.value?.open();
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    :title="titulo"
    :description="ajuda"
    width="2xl"
    position="top"
    overflow-y-auto
    @confirm="enviar"
    @close="aoFechar"
  >
    <div
      v-if="tipo"
      :key="abertura"
      class="grid gap-6 md:grid-cols-[minmax(0,1fr)_17rem]"
    >
      <div class="flex flex-col gap-4 min-w-0" data-campos>
        <template v-if="tipo === 'botaoDeLink'">
          <TextArea
            v-model="campos.mensagem"
            :label="rotulo('MENSAGEM')"
            :max-length="LIMITES.mensagem"
            :message="erroDe('mensagem')"
            :message-type="erroDe('mensagem') ? 'error' : 'info'"
            auto-height
          />
          <Input
            v-model="campos.nomeDoBotao"
            :label="rotulo('NOME_DO_BOTAO')"
            :placeholder="rotulo('NOME_DO_BOTAO_EXEMPLO')"
            :message="erroDe('nomeDoBotao')"
            :message-type="erroDe('nomeDoBotao') ? 'error' : 'info'"
          />
          <Input
            v-model="campos.endereco"
            type="url"
            :label="rotulo('ENDERECO')"
            placeholder="https://"
            :message="erroDe('endereco')"
            :message-type="erroDe('endereco') ? 'error' : 'info'"
          />
        </template>

        <template v-else-if="tipo === 'opcoes'">
          <Input
            v-model="campos.cabecalho"
            :label="rotulo('CABECALHO')"
            :message="erroDe('cabecalho') || rotulo('CABECALHO_AJUDA')"
            :message-type="erroDe('cabecalho') ? 'error' : 'info'"
            wrap-message
          />
          <TextArea
            v-model="campos.mensagem"
            :label="rotulo('MENSAGEM')"
            :max-length="LIMITES.mensagem"
            :message="erroDe('mensagem')"
            :message-type="erroDe('mensagem') ? 'error' : 'info'"
            auto-height
          />
          <fieldset class="flex flex-col gap-2 min-w-0">
            <legend class="mb-1 text-sm font-medium text-n-slate-12">
              {{ rotulo('OPCOES') }}
            </legend>
            <Input
              v-for="(_, indice) in campos.opcoes"
              :key="indice"
              v-model="campos.opcoes[indice]"
              :placeholder="
                t('CONVERSA_CANAL.JANELA.OPCOES.OPCAO_N', { n: indice + 1 })
              "
            />
            <p v-if="erroDe('opcoes')" class="text-xs text-n-ruby-11">
              {{ erroDe('opcoes') }}
            </p>
            <Button
              v-if="podeMaisOpcao"
              type="button"
              variant="link"
              color="teal"
              sm
              icon="i-lucide-plus"
              class="self-start"
              :label="rotulo('MAIS_UMA')"
              @click="campos.opcoes.push('')"
            />
          </fieldset>
          <Input
            v-if="ehLista"
            v-model="campos.nomeDaLista"
            :label="rotulo('NOME_DA_LISTA')"
            :message="erroDe('nomeDaLista') || rotulo('NOME_DA_LISTA_AJUDA')"
            :message-type="erroDe('nomeDaLista') ? 'error' : 'info'"
            wrap-message
          />
        </template>

        <template v-else-if="tipo === 'enquete'">
          <TextArea
            v-model="campos.pergunta"
            :label="rotulo('PERGUNTA')"
            :max-length="LIMITES.perguntaDaEnquete"
            :message="erroDe('pergunta')"
            :message-type="erroDe('pergunta') ? 'error' : 'info'"
            auto-height
          />
          <fieldset class="flex flex-col gap-2 min-w-0">
            <legend class="mb-1 text-sm font-medium text-n-slate-12">
              {{ rotulo('OPCOES') }}
            </legend>
            <Input
              v-for="(_, indice) in campos.opcoes"
              :key="indice"
              v-model="campos.opcoes[indice]"
              :placeholder="
                t('CONVERSA_CANAL.JANELA.OPCOES.OPCAO_N', { n: indice + 1 })
              "
            />
            <p v-if="erroDe('opcoes')" class="text-xs text-n-ruby-11">
              {{ erroDe('opcoes') }}
            </p>
            <Button
              v-if="podeMaisOpcao"
              type="button"
              variant="link"
              color="teal"
              sm
              icon="i-lucide-plus"
              class="self-start"
              :label="rotulo('MAIS_UMA')"
              @click="campos.opcoes.push('')"
            />
          </fieldset>
          <label
            class="flex items-center gap-3 min-h-11 text-sm text-n-slate-12 cursor-pointer"
          >
            <Checkbox v-model="campos.variasRespostas" />
            {{ rotulo('VARIAS_RESPOSTAS') }}
          </label>
        </template>

        <template v-else-if="tipo === 'localizacao'">
          <CampoDeBusca
            :label="rotulo('BUSCAR')"
            :placeholder="rotulo('BUSCAR_EXEMPLO')"
            :buscar="buscarLugar"
            :erro="
              erroDe('coordenadas') && !verCoordenadas
                ? rotulo('ESCOLHA_UM')
                : ''
            "
            icone="i-ph-map-pin"
            @escolher="escolherLugar"
          />
          <Input
            v-model="campos.nome"
            :label="rotulo('NOME')"
            :message="erroDe('nome')"
            :message-type="erroDe('nome') ? 'error' : 'info'"
          />
          <Input
            v-model="campos.endereco"
            :label="rotulo('ENDERECO')"
            :message="erroDe('endereco')"
            :message-type="erroDe('endereco') ? 'error' : 'info'"
          />
          <Button
            v-if="!verCoordenadas"
            type="button"
            variant="link"
            color="slate"
            sm
            class="self-start"
            :label="rotulo('TENHO_COORDENADAS')"
            @click="verCoordenadas = true"
          />
          <Input
            v-else
            v-model="campos.coordenadas"
            :label="rotulo('COORDENADAS')"
            :placeholder="rotulo('COORDENADAS_EXEMPLO')"
            :message="erroDe('coordenadas') || rotulo('COORDENADAS_AJUDA')"
            :message-type="erroDe('coordenadas') ? 'error' : 'info'"
            wrap-message
          />
        </template>

        <template v-else-if="tipo === 'pedidoDeLocalizacao'">
          <TextArea
            v-model="campos.mensagem"
            :label="rotulo('MENSAGEM')"
            :max-length="LIMITES.mensagem"
            :message="erroDe('mensagem')"
            :message-type="erroDe('mensagem') ? 'error' : 'info'"
            auto-height
          />
        </template>

        <template v-else-if="tipo === 'contato'">
          <CampoDeBusca
            v-model="campos.nome"
            :label="rotulo('NOME')"
            :placeholder="rotulo('NOME_EXEMPLO')"
            :ajuda="rotulo('NOME_AJUDA')"
            :erro="erroDe('nome')"
            :buscar="buscarContato"
            icone="i-ph-user"
            @escolher="escolherContato"
          />
          <CampoDeTelefone
            :key="abertura"
            v-model="campos.telefone"
            :label="rotulo('TELEFONE')"
            :rotulo-do-pais="rotulo('PAIS')"
            :ajuda="rotulo('TELEFONE_AJUDA')"
            :erro="erroDe('telefone')"
          />
        </template>

        <template v-else-if="tipo === 'formulario'">
          <div class="flex flex-col gap-1 min-w-0">
            <span class="text-sm font-medium text-n-slate-12">
              {{ rotulo('QUAL') }}
            </span>
            <ChoiceSelect
              v-model="campos.formulario"
              :options="formularios"
              :aria-label="rotulo('QUAL')"
              :placeholder="rotulo('ESCOLHA')"
              :invalid="Boolean(erroDe('formulario'))"
            />
            <p v-if="erroDe('formulario')" class="text-xs text-n-ruby-11">
              {{ erroDe('formulario') }}
            </p>
          </div>
          <TextArea
            v-model="campos.mensagem"
            :label="rotulo('MENSAGEM')"
            :max-length="LIMITES.mensagem"
            :message="erroDe('mensagem')"
            :message-type="erroDe('mensagem') ? 'error' : 'info'"
            auto-height
          />
          <Input
            v-model="campos.textoDoBotao"
            :label="rotulo('TEXTO_DO_BOTAO')"
            :message="erroDe('textoDoBotao')"
            :message-type="erroDe('textoDoBotao') ? 'error' : 'info'"
          />
        </template>
        <p v-if="falha" class="text-sm text-n-ruby-11" role="alert">
          {{ falha }}
        </p>
      </div>

      <div class="flex flex-col gap-2 min-w-0">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSA_CANAL.JANELA.PREVIA') }}
        </span>
        <PreviaDoMais :tipo="tipo" :campos="campos" :vira-texto="emTexto" />
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-end w-full gap-3">
        <Button
          type="button"
          variant="faded"
          color="slate"
          :label="t('CONVERSA_CANAL.JANELA.CANCELAR')"
          @click="fechar"
        />
        <Button
          type="submit"
          color="teal"
          icon="i-ph-paper-plane-right-fill"
          :is-loading="enviando"
          :disabled="enviando"
          :label="t('CONVERSA_CANAL.JANELA.ENVIAR')"
          data-enviar-do-mais
        />
      </div>
    </template>
  </Dialog>
</template>
