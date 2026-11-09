// #2414 F5 — a receita lida em frase. A frase de cada gatilho, operador, valor e
// passo é a chave do catálogo (AUTOMACAO_LIVRE.*). Das escolhas da conta, só a
// etiqueta entra, porque vai pelo nome; pessoa, time e caixa ficam no "Alterar".
import { entradaDoPasso, lerCampo } from './catalogo';
import { comColchetes } from './texto';
import { fraseDaCampanha } from './campanha';
import { fraseDoRetorno } from './retorno';
import { fraseDoWebhook } from './webhook';
import { formatAttributeDate } from 'dashboard/helper/attributeDate';

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
  // #2709: o lembrete diz quanto tempo antes da reunião ("1 dia").
  antes: (valor, t) =>
    Number.isInteger(valor?.valor) && valor?.unidade
      ? t(`${P}.DURACAO`, {
          valor: valor.valor,
          unidade: t(
            `AUTOMACAO_LIVRE.UNIDADES.${valor.unidade.toUpperCase()}`,
            {},
            valor.valor
          ),
        })
      : undefined,
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

// G32: a página de agendamento entra só como fim da frase ("..., pela página
// Renovação"), como o "repete": ela é opcional e não muda a frase do funil.
const FIM_DA_FRASE = ['repete', 'pagina'];
// Sem o nome (página que a pessoa não lê ou que saiu), a frase diz que há
// filtro de página em vez de parecer "qualquer reunião".
const comPagina = (frase, gatilho, t, nomes) => {
  if (!gatilho?.pagina_id) return frase;
  const pagina =
    nomes.pagina?.[gatilho.pagina_id] ||
    t('AUTOMACAO_LIVRE.GATILHO_DE_REUNIAO.PAGINA_SEM_NOME');
  return t('AUTOMACAO_LIVRE.GATILHO_NA_PAGINA', { frase, pagina });
};

// #2680: a caixa por onde a mensagem abre a conversa de quem não tem uma.
const comCaixa = (frase, gatilho, t, nomes) => {
  const caixa = nomes.caixa?.[gatilho.conversa_nova?.caixa_id];
  return caixa
    ? t('AUTOMACAO_LIVRE.CONVERSA_NOVA.NA_FRASE', { frase, caixa })
    : frase;
};

// #2635 (G7): o recorrente diz quando ("Toda segunda, às 8h") e em quem ("nos
// cards escolhidos"). A seleção fica no "Alterar"; aqui, só se é card, contato
// ou a conta (o da conta roda uma vez, sem seleção).
const R = 'AUTOMACAO_LIVRE.GATILHO_RECORRENTE';
const DIA_DO_RECORRENTE = {
  semanal: (gatilho, t) =>
    Number.isInteger(gatilho.dia_da_semana)
      ? t(`${R}.DIAS_DA_SEMANA.${gatilho.dia_da_semana}`)
      : undefined,
  mensal: gatilho =>
    Number.isInteger(gatilho.dia_do_mes) ? gatilho.dia_do_mes : undefined,
  diaria: () => '',
  // #2681: a data no idioma do painel ("26/11/2026", "11/26/2026").
  uma_vez: (gatilho, _t, idioma) =>
    formatAttributeDate(gatilho.data, idioma) || undefined,
};
const fraseDoRecorrente = (gatilho, entrada, t, idioma) => {
  const dia = DIA_DO_RECORRENTE[gatilho.frequencia]?.(gatilho, t, idioma);
  if (dia === undefined || !Number.isInteger(gatilho.hora))
    return t(entrada.frase);
  const ALVOS = { Contact: 'CONTATOS', Account: 'CONTA' };
  const alvo = t(`${R}.${ALVOS[entrada.alvo] || 'CARDS'}`);
  return t(`${R}.FRASE.${gatilho.frequencia.toUpperCase()}`, {
    dia,
    hora: gatilho.hora,
    alvo,
  });
};

const fraseSemPagina = (gatilho, catalogo, t, nomes, idioma) => {
  const entrada = catalogo?.gatilhos.find(item => item.tipo === gatilho?.tipo);
  if (!entrada) return t(`${P}.FALTA_GATILHO`);
  if ((entrada.parametros || []).some(item => item.peca === 'frequencia'))
    return comCaixa(
      fraseDoRecorrente(gatilho, entrada, t, idioma),
      gatilho,
      t,
      nomes
    );
  // #2678: o "repete" é opcional e entra só como fim da frase ("..., todo ano").
  const parametros = (entrada.parametros || []).filter(
    item => !FIM_DA_FRASE.includes(item.peca)
  );
  const escolhidos = Object.fromEntries(
    parametros.map(item => [
      item.peca,
      valorNaFrase(item.peca, gatilho[item.nome], t, nomes, entrada.alvo),
    ])
  );
  const completo = Object.values(escolhidos).every(
    valor => valor !== undefined && valor !== null && valor !== ''
  );
  if (!parametros.length || !completo)
    return comCaixa(t(entrada.frase), gatilho, t, nomes);
  const base = t(chaveDaFrase(entrada, gatilho), escolhidos);
  const frase =
    gatilho.repete === 'todo_ano'
      ? t('AUTOMACAO_LIVRE.GATILHO_TODO_ANO', { frase: base })
      : base;
  const funil = nomes.funilDaEtapa?.[gatilho.etapa_id];
  return comCaixa(
    funil ? t('AUTOMACAO_LIVRE.GATILHO_NO_FUNIL', { frase, funil }) : frase,
    gatilho,
    t,
    nomes
  );
};

// `idioma`: o locale do painel, para a data da frase ("pt_BR").
export const fraseDoGatilho = (gatilho, catalogo, t, nomes, idioma) => {
  const daConta = nomes || {};
  return comPagina(
    fraseSemPagina(gatilho, catalogo, t, daConta, idioma),
    gatilho,
    t,
    daConta
  );
};

// "Status da conversa", ou "Campo personalizado do contato: placa".
export const fraseDoValor = (caminho, catalogo, t) => {
  const valores = catalogo?.valores || [];
  const fixo = valores.find(
    item => item.caminho === caminho && !item.atributos
  );
  // #2679: o texto da IA (comTextosDaIa) chega com o rótulo pronto, sem frase.
  if (fixo) return fixo.rotulo || t(fixo.frase);
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
// #2702 G29: a etiqueta com o nome de um dado ({ $valor }) sai pelo nome dele,
// entre colchetes, como no texto da mensagem.
const fraseDasEtiquetas = (passo, entrada, catalogo, t) => {
  const chave = `${P}.${ETIQUETAS_DE[entrada.nome]}`;
  const nomeDaEtiqueta = item =>
    item?.$valor ? comColchetes(fraseDoValor(item.$valor, catalogo, t)) : item;
  const [por, tirar] = ['por', 'tirar'].map(nome =>
    (lerCampo(passo, entrada, nome) || []).map(nomeDaEtiqueta)
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
// G31: os nomes dos caminhos que decidem de novo ("nenhum" pelo nome da tela).
const nomesDoDeNovo = (passo, t) =>
  emLista(
    (passo.de_novo.caminhos || []).map(chave =>
      chave === 'nenhum'
        ? t(`${P}.NENHUM_SE_APLICA`)
        : (passo.caminhos || []).find(caminho => caminho.chave === chave)
            ?.nome || chave
    ),
    t
  );
const FRASE_DA_IA = {
  decidir: (passo, t, catalogo) => {
    const frase = t(
      `${P}.${escrito(passo.pergunta) ? 'DECIDIR' : 'DECIDIR_SEM_PERGUNTA'}`,
      {
        pergunta: curto(escrito(passo.pergunta)),
        n: (passo.caminhos || []).length,
      }
    );
    return passo.de_novo
      ? t(`${P}.DECIDIR_DE_NOVO`, {
          frase,
          caminhos: nomesDoDeNovo(passo, t) || '…',
          prazo: fraseDaDuracao(passo.de_novo.prazo, catalogo, t),
        })
      : frase;
  },
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
      `${P}.ESCREVER_${(passo.destino || 'sugestao').toUpperCase()}${
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
  if (FRASE_DA_IA[passo.tipo])
    return FRASE_DA_IA[passo.tipo](passo, t, catalogo);
  if (passo.tipo === 'campanha') return fraseDaCampanha(passo, t);
  if (passo.tipo === 'retorno')
    return fraseDoRetorno(passo, t, {
      quando: fraseDaDuracao(passo.daqui, catalogo, t),
      titulo: fraseDoTexto(passo.titulo, catalogo, t),
      mensagem: passo.envio && fraseDoTexto(passo.envio.mensagem, catalogo, t),
    });
  if (passo.tipo === 'webhook') return fraseDoWebhook(passo, t);
  if (passo.tipo !== 'acao') return t(entrada.frase);
  if (ETIQUETAS_DE[entrada.nome])
    return fraseDasEtiquetas(passo, entrada, catalogo, t);
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
  const { de, mais, fim_do: fimDo } = data || {};
  const inicio = de === 'hoje' ? t(`${A}.HOJE`) : rotular(de?.$valor);
  const n = Math.abs(mais?.valor || 0);
  const somada = n
    ? t(`${A}.DATA_${mais.valor < 0 ? 'MENOS' : 'MAIS'}`, {
        de: inicio,
        n,
        unidade: t(
          `AUTOMACAO_LIVRE.UNIDADES.${mais.unidade.toUpperCase()}`,
          {},
          n
        ),
      })
    : inicio;
  // #2705: "hoje + 1 mês, no fim do mês".
  return fimDo === 'mes' ? t(`${A}.DATA_FIM_DO_MES`, { data: somada }) : somada;
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
