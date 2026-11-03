// #2414 F5 — a receita lida em frase. A frase de cada gatilho, operador, valor e
// passo é a chave do catálogo (AUTOMACAO_LIVRE.*). Das escolhas da conta, só a
// etiqueta entra, porque vai pelo nome; pessoa, time e caixa ficam no "Alterar".
import { entradaDoPasso, lerCampo } from './catalogo';

const P = 'AUTOMACAO_LIVRE.FRASES';

export const fraseDoGatilho = (gatilho, catalogo, t) => {
  const entrada = catalogo?.gatilhos.find(item => item.tipo === gatilho?.tipo);
  return entrada ? t(entrada.frase) : t(`${P}.FALTA_GATILHO`);
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
  const [nome, campo] = ESCOLHA_DO_VALOR[caminho] || [];
  const passo = catalogo?.passos.find(item => item.nome === nome);
  return passo?.campos.find(item => item.nome === campo)?.opcoes || null;
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
  const operador = catalogo?.operadores.find(item => item.op === condicao.op);
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

export const fraseDaDuracao = (duracao, catalogo, t) => {
  const unidade = catalogo?.unidades.find(
    item => item.valor === duracao?.unidade
  );
  return t(`${P}.DURACAO`, {
    valor: duracao?.valor ?? '',
    unidade: unidade ? t(unidade.frase) : '',
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
  if (!entrada)
    return t(`${P}.AVANCADA`, { descricao: passo.descricao || passo.acao });
  if (passo.tipo !== 'acao') return t(entrada.frase);
  if (ETIQUETAS_DE[entrada.nome]) return fraseDasEtiquetas(passo, entrada, t);
  return [t(entrada.frase), ...resumoDaAcao(passo, entrada, t)].join(' · ');
};
