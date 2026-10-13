// Adaptador HTTP da tela de Modelos do WhatsApp: a API de Modelos (#1330) e os
// endpoints da tela (#1332), no formato que a tela usa (./modelosWhatsapp.js).
// A Meta trabalha por conta do WhatsApp (WABA): cada grupo de caixas da mesma
// conta é lido e alterado por uma caixa dele.
import api from 'dashboard/api/whatsappTemplates';
import { arquivoGuardado, esquecerArquivos } from './arquivos';
import { SITUACOES_FORA_DA_LISTA, modeloDaMeta } from './daMeta';
import { corpoParaAlterar, corpoParaCriar } from '../helpers/paraMeta';
import { motivoDaPausa } from '../helpers/motivoDaPausa';

export { motivoDaPausa };

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

// Erro com o texto que o servidor mandou (já traduzido), para a tela mostrar.
export class ErroDaApi extends Error {
  constructor(erro) {
    const dados = erro?.response?.data || {};
    super(dados.error || 'erro');
    this.codigo = dados.error || '';
    this.mensagem = dados.message || '';
    this.status = erro?.response?.status || 0;
    // #1382: por que o "Atualizar" não deu certo (meta_unreachable, permission_denied…).
    this.motivo = dados.code || '';
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
let contaDoCache = null;

const esquecerLista = () => {
  lista = null;
};

// O que fica guardado é de uma conta só: trocou de conta (sem recarregar a página),
// começa de novo.
const contaAtual = () => window.location.pathname.split('/')[3] || '';
const conferirConta = () => {
  if (contaDoCache === contaAtual()) return;
  contaDoCache = contaAtual();
  lista = null;
  caixas = null;
  precos = null;
};

const numeroDaCaixa = caixa => ({
  id: caixa.id,
  nome: caixa.name,
  telefone: caixa.phone_number || '',
  conta: { id: caixa.group_id, nome: caixa.group_name },
  situacao: caixa.reconnect ? 'reconectar' : 'conectada',
});

const lerCaixas = () => {
  conferirConta();
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

// Pedir a lista nova à Meta pode falhar (#1382): aí vale a lista guardada, sem
// `refresh`, e a tela avisa que não atualizou (com o porquê), sem dizer que é nova.
const lerPayloadDoGrupo = async (grupo, atualizar) => {
  try {
    const { payload } = await chamar(
      api.getTemplates(grupo.id, { refresh: atualizar })
    );
    return { payload, naoAtualizou: null };
  } catch (erro) {
    if (!atualizar || erro.codigo !== 'sync_failed') throw erro;
    const { payload } = await chamar(api.getTemplates(grupo.id));
    return {
      payload,
      naoAtualizou: { conta: grupo.conta.nome, motivo: erro.motivo },
    };
  }
};

const lerModelosDoGrupo = async (grupo, atualizar) => {
  const { payload, naoAtualizou } = await lerPayloadDoGrupo(grupo, atualizar);
  const modelos = payload
    .filter(
      template =>
        !SITUACOES_FORA_DA_LISTA.includes(String(template.status).toUpperCase())
    )
    .map(template => modeloDaMeta(template, grupo));
  modelos.naoAtualizou = naoAtualizou;
  return modelos;
};

const lerModelos = async atualizar => {
  const grupos = gruposDe(await lerCaixas());
  const resultados = await Promise.allSettled(
    grupos.map(grupo => lerModelosDoGrupo(grupo, atualizar))
  );
  const lidos = resultados.filter(item => item.status === 'fulfilled');
  if (grupos.length && !lidos.length) throw resultados[0].reason;
  const modelos = lidos.flatMap(item => item.value);
  // Uma conta do WhatsApp não respondeu: a lista avisa que pode faltar modelo.
  modelos.parcial = lidos.length < grupos.length;
  modelos.naoAtualizou = lidos
    .map(item => item.value.naoAtualizou)
    .filter(Boolean);
  return modelos;
};

const listarModelos = ({ atualizar = false } = {}) => {
  conferirConta();
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

// "Onde está em uso" (#1330) → a lista da tela. Tudo ali ainda vai sair, por
// isso bloqueia apagar e alterar. O que a pessoa não vê vem só como aviso.
// `data` (ISO) a tela formata no idioma dela (ModeloUsos).
export const usosDaApi = uso => [
  ...(uso.campaigns || []).map(campanha => ({
    tipo: 'campanha',
    nome: campanha.title,
    data: campanha.scheduled_at || null,
    // Parada pelo modelo: não trava alterar (corrigir é o caminho de volta), só apagar.
    pausada: Boolean(campanha.paused),
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
    data: retorno.due_at || null,
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

const ondeEstaEmUso = async id => {
  const modelo = await obterModelo(id);
  return usosDaApi(await chamar(api.getUsage(modelo.caixa, modelo.id)));
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
      // O modelo já está aprovado e igual ao que a campanha guardou (o servidor confere).
      podeRetomar: Boolean(pausa.ready_to_resume),
    };
  });
};

const retomarCampanha = pausaId => chamar(api.resumeCampaignPause(pausaId));

const lerPrecos = () => {
  conferirConta();
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
// diferentes, cada um com a sua análise. Devolve a lista criada. Se uma conta
// falhar depois de outra já ter criado, devolve as criadas com `falha` (o erro),
// para a tela não mandar de novo o que já foi.
const criarModelo = async (rascunho, { textos } = {}) => {
  const grupos = gruposDe(await lerCaixas()).filter(grupo =>
    grupo.numeros.some(id => rascunho.numeros.includes(id))
  );
  const criados = [];
  try {
    // eslint-disable-next-line no-restricted-syntax
    for (const grupo of grupos) {
      // eslint-disable-next-line no-await-in-loop
      const midias = await subirArquivos(rascunho.conteudo, grupo.id);
      // eslint-disable-next-line no-await-in-loop
      const criado = await chamar(
        api.createTemplate(
          grupo.id,
          corpoParaCriar(rascunho, { midias, textos })
        )
      );
      criados.push(modeloDaMeta(criado, grupo));
    }
  } catch (erro) {
    if (!criados.length) throw erro;
    criados.falha = erro;
  } finally {
    esquecerLista();
  }
  if (!criados.falha) esquecerArquivos(rascunho.conteudo);
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
  esquecerArquivos(rascunho.conteudo);
  // O grupo do modelo como estava: a caixa pode ter saído da conta no meio do caminho.
  return modeloDaMeta(alterado, {
    id: modelo.caixa,
    conta: { id: modelo.conta },
    numeros: modelo.numeros,
    envios: null,
  });
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
