// #2414 F5 — a receita lida em frase. A frase de cada gatilho, operador, valor e
// passo é a chave do catálogo (AUTOMACAO_LIVRE.*). Das escolhas da conta, só a
// etiqueta entra, porque vai pelo nome; pessoa, time e caixa ficam no "Alterar".
import { entradaDoPasso, lerCampo } from './catalogo';
import { comColchetes } from './texto';
import { fraseDoRetorno } from './retorno';
import {
  TIPO as EM_OUTRO_REGISTRO,
  fraseDoOutroRegistro,
} from './outroRegistro';

const P = 'AUTOMACAO_LIVRE.FRASES';

// #2499: o gatilho com a etapa ou o funil escolhidos diz o nome deles
// ("Quando o card entra em Orçamento"). `nomes` vem pela peça do parâmetro
// ({ etapa: { 12: 'Orçamento' }, funil: {...} }); o campo de data, também pelo
// alvo ({ campo: { Contact: { aniversario: 'Aniversário' } } }). Os de tempo
// dizem os dias e a hora pelo número e o "antes"/"depois" em frase. Sem o nome
// na tela, ou sem o funil (vale qualquer um), fica a frase do catálogo. Com
// mais de um funil na conta, `nomes.funilDaEtapa` acrescenta o funil da etapa
// ("..., no funil X").
const QUANDO_DA_DATA = ['antes', 'depois'];
const numero = valor => (Number.isInteger(valor) ? valor : undefined);
const VALOR_DA_PECA = {
  dias: numero,
  hora: numero,
  quando: (valor, t) =>
    QUANDO_DA_DATA.includes(valor)
      ? t(`AUTOMACAO_LIVRE.QUANDO_DA_DATA.${valor.toUpperCase()}`)
      : undefined,
  campo: (valor, t, nomes, alvo) => nomes.campo?.[alvo]?.[valor],
};
const valorNaFrase = (peca, valor, t, nomes, alvo) =>
  VALOR_DA_PECA[peca]
    ? VALOR_DA_PECA[peca](valor, t, nomes, alvo)
    : nomes[peca]?.[valor];

// No próprio dia da data (dias = 0), a frase dos de data não fala em dias.
const chaveDaFrase = (entrada, gatilho) => {
  const chave = entrada.frase.split('.').pop();
  const temQuando = entrada.parametros.some(item => item.peca === 'quando');
  return temQuando && gatilho.dias === 0
    ? `AUTOMACAO_LIVRE.GATILHO_NO_DIA.${chave}`
    : `AUTOMACAO_LIVRE.GATILHO_COM.${chave}`;
};

export const fraseDoGatilho = (gatilho, catalogo, t, nomes = {}) => {
  const entrada = catalogo?.gatilhos.find(item => item.tipo === gatilho?.tipo);
  if (!entrada) return t(`${P}.FALTA_GATILHO`);
  const parametros = entrada.parametros || [];
  const escolhidos = Object.fromEntries(
    parametros.map(item => [
      item.peca,
      valorNaFrase(item.peca, gatilho[item.nome], t, nomes, entrada.alvo),
    ])
  );
  const completo = Object.values(escolhidos).every(
    valor => valor !== undefined && valor !== null && valor !== ''
  );
  if (!parametros.length || !completo) return t(entrada.frase);
  const frase = t(chaveDaFrase(entrada, gatilho), escolhidos);
  const funil = nomes.funilDaEtapa?.[gatilho.etapa_id];
  return funil
    ? t('AUTOMACAO_LIVRE.GATILHO_NO_FUNIL', { frase, funil })
    : frase;
};

// "Status da conversa", ou "Campo personalizado do contato: placa".
export const fraseDoValor = (caminho, catalogo, t) => {
  const valores = catalogo?.valores || [];
  const fixo = valores.find(
    item => item.caminho === caminho && !item.atributos
  );
  if (fixo) return t(fixo.frase);
  const base = valores.find(
    item => item.atributos && caminho?.startsWith(`${item.caminho}.`)
  );
  if (base)
    return t(`${P}.ATRIBUTO`, {
      base: t(base.frase),
      chave: caminho.slice(base.caminho.length + 1),
    });
  return caminho || '';
};

// Status e prioridade da conversa têm valores fechados: os mesmos que os passos
// "Mudar o status" e "Mudar a prioridade" escolhem. A condição mostra e escolhe
// por essas opções ("Aberta"), nunca pelo valor gravado ("open").
const ESCOLHA_DO_VALOR = {
  'conversa.status': ['conversa_status', 'status'],
  'conversa.prioridade': ['conversa_prioridade', 'priority'],
};
export const opcoesDoValor = (caminho, catalogo) => {
  const proprias = catalogo?.valores?.find(
    item => item.caminho === caminho
  )?.opcoes;
  if (proprias) return proprias;
  const [nome, campo] = ESCOLHA_DO_VALOR[caminho] || [];
  const passo = catalogo?.passos.find(item => item.nome === nome);
  return passo?.campos.find(item => item.nome === campo)?.opcoes || null;
};

// O valor que traz operadores próprios ("é", "não é") só compara por eles; os
// outros, por todos. `pede_valor` vem sempre do operador do esquema.
export const operadoresDoValor = (caminho, catalogo) => {
  const todos = catalogo?.operadores || [];
  const proprios = catalogo?.valores?.find(
    item => item.caminho === caminho
  )?.operadores;
  if (!proprios) return todos;
  return proprios.map(item => ({
    ...todos.find(op => op.op === item.op),
    ...item,
  }));
};

export const fraseDaCondicao = (condicao, catalogo, t) => {
  if (!condicao) return t(`${P}.FALTA_CONDICAO`);
  const grupo = condicao.todas ? 'TODAS' : condicao.alguma && 'ALGUMA';
  if (grupo) {
    const lista = (condicao.todas || condicao.alguma)
      .map(item => fraseDaCondicao(item, catalogo, t))
      .join('; ');
    return t(`${P}.${grupo}`, { lista });
  }
  const operador = operadoresDoValor(condicao.campo?.$valor, catalogo).find(
    item => item.op === condicao.op
  );
  const campo = fraseDoValor(condicao.campo?.$valor, catalogo, t);
  const op = operador ? t(operador.frase) : condicao.op;
  if (operador && !operador.pede_valor)
    return t(`${P}.CONDICAO_SEM_VALOR`, { campo, op });
  let valor = condicao.valor;
  const opcao = opcoesDoValor(condicao.campo?.$valor, catalogo)?.find(
    item => item.valor === valor
  );
  if (opcao) valor = t(opcao.frase);
  if (typeof valor === 'boolean') valor = t(`${P}.${valor ? 'SIM' : 'NAO'}`);
  return t(`${P}.CONDICAO`, { campo, op, valor: valor ?? '' });
};

// A unidade concorda com o número: "1 dia", "2 dias". Sem número, o plural.
export const contagemDaDuracao = valor => (Number.isInteger(valor) ? valor : 2);

export const fraseDaDuracao = (duracao, catalogo, t) => {
  const unidade = catalogo?.unidades.find(
    item => item.valor === duracao?.unidade
  );
  return t(`${P}.DURACAO`, {
    valor: duracao?.valor ?? '',
    unidade: unidade
      ? t(unidade.frase, {}, contagemDaDuracao(duracao?.valor))
      : '',
  });
};

// O que cada campo escolheu e cabe numa linha: a opção ("Mudar o status da
// conversa · Resolvida"). Texto livre e ids da conta não entram; aparecem no
// "Alterar".
const resumoDoCampo = (campo, valor, t) => {
  if (!campo.opcoes) return null;
  const opcao = campo.opcoes.find(item => item.valor === valor);
  return opcao ? t(opcao.frase) : null;
};

// Pôr e tirar etiqueta é uma ação só; a frase diz o que ela faz com as
// escolhidas: "Pôr a etiqueta vip na conversa", "No contato, pôr vip e tirar
// lead". Sem nenhuma escolhida, fica a frase do catálogo.
const ETIQUETAS_DE = {
  conversa_etiquetas: 'ETIQUETAS_CONVERSA',
  contato_etiquetas: 'ETIQUETAS_CONTATO',
};
const emLista = (nomes, t) =>
  nomes.length > 1
    ? t(`${P}.LISTA`, {
        inicio: nomes.slice(0, -1).join(', '),
        ultimo: nomes[nomes.length - 1],
      })
    : nomes[0];
const fraseDasEtiquetas = (passo, entrada, t) => {
  const chave = `${P}.${ETIQUETAS_DE[entrada.nome]}`;
  const [por, tirar] = ['por', 'tirar'].map(
    nome => lerCampo(passo, entrada, nome) || []
  );
  if (por.length && tirar.length)
    return t(`${chave}.POR_E_TIRAR`, {
      por: emLista(por, t),
      tirar: emLista(tirar, t),
    });
  const [nomes, acao] = por.length ? [por, 'POR'] : [tirar, 'TIRAR'];
  if (!nomes.length) return t(entrada.frase);
  return t(`${chave}.${acao}${nomes.length > 1 ? '_VARIAS' : ''}`, {
    lista: emLista(nomes, t),
  });
};

const resumoDaAcao = (passo, entrada, t) =>
  entrada.campos
    .map(campo => resumoDoCampo(campo, lerCampo(passo, entrada, campo.nome), t))
    .filter(Boolean);

// O texto de "mensagem" e "avisar" (e o assunto do "email") na linha: os dados entre colchetes, pelo
// nome do catálogo; texto longo corta, e o inteiro fica no "Alterar".
const CABE_NA_LINHA = 60;
const fraseDoTexto = (partes, catalogo, t) => {
  const texto = (partes || [])
    .map(parte =>
      typeof parte === 'string'
        ? parte
        : comColchetes(fraseDoValor(parte.$valor, catalogo, t))
    )
    .join('')
    .trim();
  if (!texto) return t(`${P}.FALTA_TEXTO`);
  return texto.length > CABE_NA_LINHA
    ? `${texto.slice(0, CABE_NA_LINHA).trimEnd()}…`
    : texto;
};

// Quem o "avisar" chama: o responsável e quantos times e pessoas. Os nomes
// ficam no "Alterar", como os das outras escolhas da conta.
const quemAvisar = (para, t) => {
  const quem = [
    para?.responsavel && t(`${P}.RESPONSAVEL`),
    para?.times?.length &&
      t(`${P}.TIMES`, { n: para.times.length }, para.times.length),
    para?.pessoas?.length &&
      t(`${P}.PESSOAS`, { n: para.pessoas.length }, para.pessoas.length),
  ].filter(Boolean);
  if (!quem.length) return t(`${P}.AVISAR_EQUIPE`);
  return quem.length > 1
    ? t(`${P}.LISTA`, {
        inicio: quem.slice(0, -1).join(', '),
        ultimo: quem[quem.length - 1],
      })
    : quem[0];
};

// O passo sem entrada no catálogo e sem nome (um tipo que este painel ainda não
// conhece) fica só "Ação avançada", sem os dois-pontos vazios.
const fraseAvancada = (passo, t) => {
  const nome = passo.descricao || passo.acao;
  return nome
    ? t(`${P}.AVANCADA`, { descricao: nome })
    : t(`${P}.AVANCADA_SEM_NOME`);
};

// F7: os passos de IA na linha, com o que quem montou escreveu (a pergunta, a
// instrução e o nome dos dados), nunca o que a IA respondeu.
const curto = texto =>
  texto && texto.length > CABE_NA_LINHA
    ? `${texto.slice(0, CABE_NA_LINHA).trimEnd()}…`
    : texto || '';
// Ainda sem pergunta ou instrução, a linha diz o que falta, sem aspas vazias.
const escrito = texto => (texto || '').trim();
const FRASE_DA_IA = {
  decidir: (passo, t) =>
    t(`${P}.${escrito(passo.pergunta) ? 'DECIDIR' : 'DECIDIR_SEM_PERGUNTA'}`, {
      pergunta: curto(escrito(passo.pergunta)),
      n: (passo.caminhos || []).length,
    }),
  extrair: (passo, t) =>
    t(`${P}.EXTRAIR`, {
      lista:
        emLista(
          (passo.campos || []).map(campo => campo.chave).filter(Boolean),
          t
        ) || '…',
    }),
  escrever: (passo, t) =>
    t(
      `${P}.ESCREVER_${passo.destino === 'mensagem' ? 'MENSAGEM' : 'SUGESTAO'}${
        escrito(passo.instrucao) ? '' : '_SEM_INSTRUCAO'
      }`,
      { instrucao: curto(escrito(passo.instrucao)) }
    ),
  resumir: (passo, t) =>
    passo.destino?.avisar
      ? t(`${P}.RESUMIR_AVISAR`, { quem: quemAvisar(passo.destino.avisar, t) })
      : t(`${P}.RESUMIR_NOTA`),
};

export const fraseDoPasso = (passo, catalogo, t) => {
  const entrada = entradaDoPasso(passo, catalogo);
  if (passo.tipo === 'esperar')
    return t(`${P}.ESPERAR`, {
      duracao: fraseDaDuracao(passo.duracao, catalogo, t),
    });
  if (passo.tipo === 'esperar_ate')
    return t(`${P}.ESPERAR_ATE`, {
      condicao: fraseDaCondicao(passo.condicao, catalogo, t),
      prazo: fraseDaDuracao(passo.prazo, catalogo, t),
    });
  if (passo.tipo === 'se')
    return t(`${P}.SE`, {
      condicao: fraseDaCondicao(passo.condicao, catalogo, t),
    });
  if (!entrada) return fraseAvancada(passo, t);
  if (passo.tipo === 'mensagem')
    return t(`${P}.MENSAGEM`, {
      texto: fraseDoTexto(passo.texto, catalogo, t),
    });
  if (passo.tipo === 'email')
    return t(`${P}.EMAIL`, {
      assunto: fraseDoTexto(passo.assunto, catalogo, t),
    });
  if (passo.tipo === 'avisar')
    return t(`${P}.AVISAR`, {
      quem: quemAvisar(passo.para, t),
      texto: fraseDoTexto(passo.texto, catalogo, t),
    });
  if (FRASE_DA_IA[passo.tipo]) return FRASE_DA_IA[passo.tipo](passo, t);
  if (passo.tipo === 'retorno')
    return fraseDoRetorno(passo, t, {
      quando: fraseDaDuracao(passo.daqui, catalogo, t),
      titulo: fraseDoTexto(passo.titulo, catalogo, t),
      mensagem: passo.envio && fraseDoTexto(passo.envio.mensagem, catalogo, t),
    });
  if (passo.tipo === EM_OUTRO_REGISTRO) {
    const campo = passo.registro?.campo?.$valor;
    return fraseDoOutroRegistro(
      passo,
      t,
      campo && fraseDoValor(campo, catalogo, t)
    );
  }
  if (passo.tipo !== 'acao') return t(entrada.frase);
  if (ETIQUETAS_DE[entrada.nome]) return fraseDasEtiquetas(passo, entrada, t);
  return [t(entrada.frase), ...resumoDaAcao(passo, entrada, t)].join(' · ');
};

const A = 'AUTOMACAO_LIVRE.ALTERAR_PAINEL';

// #2414 G16b — a data calculada em frase curta: "hoje + 6 meses", "Data de
// nascimento − 1 dia". `rotular` dá o nome do campo de partida (a peça de data
// usa o nome que a pessoa vê na escolha).
export const fraseDaData = (
  data,
  catalogo,
  t,
  rotular = caminho => fraseDoValor(caminho, catalogo, t)
) => {
  const { de, mais } = data || {};
  const inicio = de === 'hoje' ? t(`${A}.HOJE`) : rotular(de?.$valor);
  if (!mais?.valor) return inicio;
  const n = Math.abs(mais.valor);
  return t(`${A}.DATA_${mais.valor < 0 ? 'MENOS' : 'MAIS'}`, {
    de: inicio,
    n,
    unidade: t(`AUTOMACAO_LIVRE.UNIDADES.${mais.unidade.toUpperCase()}`, {}, n),
  });
};

// #2414 G16 — o valor calculado que o Guia montou num campo da ação, em frase:
// "Vem da conversa: Nome do contato", "Montado na hora: indicado por [Nome do
// contato]", "Data calculada na hora: hoje + 6 meses".
export const fraseDoCalculado = (valor, catalogo, t) => {
  if (valor?.$valor)
    return t(`${A}.DA_CONVERSA`, {
      valor: fraseDoValor(valor.$valor, catalogo, t),
    });
  if (valor?.$texto)
    return t(`${A}.CALCULADO_TEXTO`, {
      texto: fraseDoTexto(valor.$texto, catalogo, t),
    });
  return t(`${A}.DATA_CALCULADA`, {
    de: fraseDaData(valor?.$data, catalogo, t),
  });
};
