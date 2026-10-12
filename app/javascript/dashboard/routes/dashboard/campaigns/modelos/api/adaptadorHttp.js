// Adaptador HTTP da tela de Modelos do WhatsApp: a API de Modelos (#1330) e os
// endpoints da tela (#1332), no formato que a tela usa (./modelosWhatsapp.js).
// A Meta trabalha por conta do WhatsApp (WABA): cada grupo de caixas da mesma
// conta é lido e alterado por uma caixa dele.
import api from 'dashboard/api/whatsappTemplates';
import { arquivoGuardado } from './arquivos';
import { SITUACOES_FORA_DA_LISTA, modeloDaMeta } from './daMeta';
import { corpoParaAlterar, corpoParaCriar } from '../helpers/paraMeta';

const DIA_MS = 24 * 60 * 60 * 1000;
const DIAS_DO_NOME_PRESO = 30;
// A lista é lida de novo depois de 30 s, ou logo depois de criar, alterar ou apagar.
const VALIDADE_DA_LISTA_MS = 30 * 1000;

const CATEGORIA_DO_PRECO = {
  aviso: 'utility',
  divulgacao: 'marketing',
  codigo: 'authentication',
  resposta: 'service',
};

// Por que a campanha parou (CampaignPause.reason_code, #1329) → motivo da tela.
const MOTIVOS_DA_PAUSA = {
  template_category_changed: 'tipo_mudou',
  template_structure_changed: 'modelo_mudou',
  template_missing: 'modelo_apagado',
  template_format_unsupported: 'formato_nao_vai',
};

// Erro com o texto que o servidor mandou (já traduzido), para a tela mostrar.
export class ErroDaApi extends Error {
  constructor(erro) {
    const dados = erro?.response?.data || {};
    super(dados.error || 'erro');
    this.codigo = dados.error || '';
    this.mensagem = dados.message || '';
    this.status = erro?.response?.status || 0;
  }
}

const chamar = async promessa => {
  try {
    const { data } = await promessa;
    return data;
  } catch (erro) {
    throw new ErroDaApi(erro);
  }
};

let lista = null; // { quando, promessa }
let caixas = null;
let precos = null;

const esquecerLista = () => {
  lista = null;
};

const numeroDaCaixa = caixa => ({
  id: caixa.id,
  nome: caixa.name,
  telefone: caixa.phone_number || '',
  conta: { id: caixa.group_id, nome: caixa.group_name },
  situacao: caixa.reconnect ? 'reconectar' : 'conectada',
});

const lerCaixas = () => {
  caixas ||= chamar(api.getInboxes()).then(({ payload }) => payload);
  caixas.catch(() => {
    caixas = null;
  });
  return caixas;
};

// Um grupo por conta do WhatsApp: a caixa que fala com a Meta (a primeira
// conectada), os números e os envios do mês somados.
const gruposDe = lidas => {
  const grupos = new Map();
  lidas.forEach(caixa => {
    const grupo = grupos.get(caixa.group_id) || {
      id: null,
      conta: { id: caixa.group_id, nome: caixa.group_name },
      numeros: [],
      envios: {},
    };
    if (!grupo.id && !caixa.reconnect) grupo.id = caixa.id;
    grupo.numeros.push(caixa.id);
    Object.entries(caixa.template_sends || {}).forEach(([nome, total]) => {
      grupo.envios[nome] = (grupo.envios[nome] || 0) + total;
    });
    grupos.set(caixa.group_id, grupo);
  });
  return [...grupos.values()].map(grupo => ({
    ...grupo,
    id: grupo.id || grupo.numeros[0],
  }));
};

const lerModelosDoGrupo = async (grupo, atualizar) => {
  const { payload } = await chamar(
    api.getTemplates(grupo.id, { refresh: atualizar })
  );
  return payload
    .filter(
      template =>
        !SITUACOES_FORA_DA_LISTA.includes(String(template.status).toUpperCase())
    )
    .map(template => modeloDaMeta(template, grupo));
};

const lerModelos = async atualizar => {
  const grupos = gruposDe(await lerCaixas());
  const resultados = await Promise.allSettled(
    grupos.map(grupo => lerModelosDoGrupo(grupo, atualizar))
  );
  const lidos = resultados.filter(item => item.status === 'fulfilled');
  if (grupos.length && !lidos.length) throw resultados[0].reason;
  return lidos.flatMap(item => item.value);
};

const listarModelos = ({ atualizar = false } = {}) => {
  const valida = lista && Date.now() - lista.quando < VALIDADE_DA_LISTA_MS;
  if (atualizar || !valida) {
    if (atualizar) caixas = null;
    const promessa = lerModelos(atualizar);
    lista = { quando: Date.now(), promessa };
    promessa.catch(esquecerLista);
  }
  return lista.promessa;
};

const obterModelo = async id => {
  const modelo = (await listarModelos()).find(item => item.id === String(id));
  if (!modelo) throw new Error('modelo_nao_encontrado');
  return modelo;
};

const quando = (iso, locale) =>
  iso
    ? new Date(iso).toLocaleDateString(
        (locale || 'pt-BR').split('_').join('-'),
        {
          day: '2-digit',
          month: '2-digit',
        }
      )
    : '';

// "Onde está em uso" (#1330) → a lista da tela. Tudo ali ainda vai sair, por
// isso bloqueia apagar e alterar. O que a pessoa não vê vem só como aviso.
export const usosDaApi = (uso, locale) => [
  ...(uso.campaigns || []).map(campanha => ({
    tipo: 'campanha',
    nome: campanha.title,
    quando: quando(campanha.scheduled_at, locale),
    agendado: true,
    rota: { name: 'campaigns_journey_index' },
  })),
  ...(uso.booking_pages || []).map(pagina => ({
    tipo: 'agendamento',
    nome: pagina.title,
    agendado: true,
    rota: { name: 'settings_booking' },
  })),
  ...(uso.follow_ups || []).map(retorno => ({
    tipo: 'crm',
    nome: retorno.title,
    quando: quando(retorno.due_at, locale),
    agendado: true,
    rota: {
      name: 'crm_kanban_index',
      query: { card_id: String(retorno.card_id) },
    },
  })),
  ...(uso.uso_oculto
    ? [{ tipo: 'oculto', nome: '', agendado: true, rota: null }]
    : []),
];

const ondeEstaEmUso = async (id, { locale } = {}) => {
  const modelo = await obterModelo(id);
  return usosDaApi(await chamar(api.getUsage(modelo.caixa, modelo.id)), locale);
};

// Por que a campanha parou → motivo da tela.
export const motivoDaPausa = pausa => {
  if (pausa.reason_code === 'template_not_approved') {
    const status = String(pausa.details?.status || '').toUpperCase();
    if (status === 'REJECTED') return 'modelo_recusado';
    if (['PAUSED', 'DISABLED'].includes(status)) return 'modelo_pausado';
    return 'modelo_em_analise';
  }
  if (pausa.source === 'system') return 'nao_conferido';
  return MOTIVOS_DA_PAUSA[pausa.reason_code] || 'outro';
};

// O modelo de uma pausa: o mesmo nome e idioma, na conta do WhatsApp da caixa da campanha.
const modeloDaPausa = (pausa, modelos) => {
  const nome = pausa.details?.template_name;
  const idioma = String(pausa.details?.language || '').toLowerCase();
  return modelos.find(
    modelo =>
      modelo.nomeNoWhatsapp === nome &&
      String(modelo.idioma || '').toLowerCase() === idioma &&
      modelo.numeros.includes(pausa.campaign?.inbox_id)
  );
};

const listarCampanhasParadas = async () => {
  const { payload } = await chamar(api.getCampaignPauses());
  const modelos = await listarModelos().catch(() => []);
  return payload.map(pausa => {
    const modelo = modeloDaPausa(pausa, modelos);
    return {
      id: pausa.campaign.id,
      pausaId: pausa.id,
      nome: pausa.campaign.title,
      modeloId: modelo?.id || null,
      modeloNome: modelo?.nome || pausa.details?.template_name || '',
      motivo: motivoDaPausa(pausa),
    };
  });
};

const retomarCampanha = pausaId => chamar(api.resumeCampaignPause(pausaId));

const lerPrecos = () => {
  precos ||= chamar(api.getPrices()).then(({ payload }) => payload);
  precos.catch(() => {
    precos = null;
  });
  return precos;
};

const custoPorEnvio = async tipo => {
  const tabela = await lerPrecos();
  const valor = tabela.prices?.[CATEGORIA_DO_PRECO[tipo]];
  return valor == null
    ? null
    : { valor: Number(valor), moeda: tabela.currency };
};

// Franquia de respostas grátis do mês, por número.
const obterFranquia = async () => {
  const tabela = await lerPrecos();
  const limite = tabela.free_tier?.service?.messages;
  if (!limite) return null;
  return {
    limite,
    numeros: (tabela.service_usage || []).map(item => ({
      id: item.inbox_id,
      nome: item.name,
      usadas: item.messages,
    })),
  };
};

// Sobe o arquivo do topo e o de cada cartão pela caixa do grupo. Sem arquivo
// novo, fica o que o modelo já tinha (handle guardado no perfil).
const subirArquivos = async (conteudo, caixa) => {
  const subir = async chave => {
    const arquivo = arquivoGuardado(chave);
    return arquivo ? chamar(api.uploadMedia(caixa, arquivo)) : null;
  };
  const topo = await subir(conteudo.topo?.local);
  const cartoes = [];
  // Um de cada vez: a Meta recebe um arquivo por sessão de upload.
  // eslint-disable-next-line no-restricted-syntax
  for (const cartao of conteudo.cartoes || []) {
    // eslint-disable-next-line no-await-in-loop
    cartoes.push(await subir(cartao.local));
  }
  return { topo, cartoes };
};

// Um modelo por conta do WhatsApp: números de contas diferentes viram modelos
// diferentes, cada um com a sua análise. Devolve a lista criada.
const criarModelo = async (rascunho, { textos } = {}) => {
  const grupos = gruposDe(await lerCaixas()).filter(grupo =>
    grupo.numeros.some(id => rascunho.numeros.includes(id))
  );
  const criados = [];
  // eslint-disable-next-line no-restricted-syntax
  for (const grupo of grupos) {
    // eslint-disable-next-line no-await-in-loop
    const midias = await subirArquivos(rascunho.conteudo, grupo.id);
    // eslint-disable-next-line no-await-in-loop
    const criado = await chamar(
      api.createTemplate(grupo.id, corpoParaCriar(rascunho, { midias, textos }))
    );
    criados.push(modeloDaMeta(criado, grupo));
  }
  esquecerLista();
  return criados;
};

const alterarModelo = async (id, rascunho, { textos } = {}) => {
  const modelo = await obterModelo(id);
  const midias = await subirArquivos(rascunho.conteudo, modelo.caixa);
  const alterado = await chamar(
    api.updateTemplate(
      modelo.caixa,
      modelo.id,
      corpoParaAlterar(rascunho, modelo, { midias, textos })
    )
  );
  esquecerLista();
  const grupo = gruposDe(await lerCaixas()).find(
    item => item.id === modelo.caixa
  );
  return modeloDaMeta(alterado, grupo);
};

const apagarModelo = async id => {
  const modelo = await obterModelo(id);
  await chamar(api.deleteTemplate(modelo.caixa, modelo.id));
  esquecerLista();
  return {
    nomeBloqueadoAte: new Date(
      Date.now() + DIAS_DO_NOME_PRESO * DIA_MS
    ).toISOString(),
  };
};

const listarCaixasDaCampanha = async () =>
  (await lerCaixas()).map(numeroDaCaixa);

const listarNumeros = async () =>
  (await listarCaixasDaCampanha()).filter(
    numero => numero.situacao === 'conectada'
  );

// Ainda sem backend (catálogo de produtos e formulários do WhatsApp): a tela
// esconde esses formatos (constants.js, FORMATOS[].disponivel).
const obterCatalogo = async () => null;
const listarFormularios = async () => [];

// Criar e melhorar com IA são a entrega E (#1333): a tela esconde as entradas
// (helpers/useCanUseIA.js) enquanto estas funções não existirem de verdade.
const iaIndisponivel = async () => {
  throw new Error('ia_indisponivel');
};

// Para os testes: começa sem nada guardado.
export const esquecerTudo = () => {
  lista = null;
  caixas = null;
  precos = null;
};

export default {
  listarNumeros,
  listarCaixasDaCampanha,
  listarModelos,
  obterModelo,
  ondeEstaEmUso,
  listarCampanhasParadas,
  retomarCampanha,
  custoPorEnvio,
  obterFranquia,
  criarModelo,
  alterarModelo,
  apagarModelo,
  obterCatalogo,
  listarFormularios,
  criarComIA: iaIndisponivel,
  melhorarComIA: iaIndisponivel,
};
