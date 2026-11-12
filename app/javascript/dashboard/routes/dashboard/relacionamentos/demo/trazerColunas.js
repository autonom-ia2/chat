// #2896 — a demonstração faz o papel do servidor nas colunas e nas perguntas:
// trocar o destino de uma coluna (app/services/relacionamentos/trazer/
// trocar_destino.rb), responder (responder.rb) e o que as perguntas e as
// respostas viram depois (perguntas.rb). Cada função recebe a leitura e devolve
// uma leitura nova, no formato que a fonte real entrega; a que não pode ser
// feita lança a mesma recusa que a fonte real lançaria (demo/trazerRecusa.js).
//   - Cada alvo (nome, telefone, e-mail, empresa) é de uma coluna só: a coluna
//     que entra num alvo toma o lugar da que estava nele, que volta a ser
//     informação. Tirar a última coluna de telefone ou e-mail é recusado.
//   - O telefone da empresa só existe com coluna de empresa; sem ela, a coluna
//     que era telefone da empresa volta a ser informação.
//   - Só a informação tem campo (o nome dele e o "para que serve").
//   - A pergunta do telefone existe enquanto a resposta dela vale (a coluna
//     está onde a resposta a pôs) ou enquanto a coluna é o telefone duvidoso.
//   - A resposta de "São clientes?" acompanha as colunas: sem coluna "cliente",
//     "algumas" deixa de valer; com uma, a resposta é "algumas" com ela, menos
//     quando a pessoa disse "sim, todas".
//   - (E3) Só uma coluna diz quem é cliente: a que vira "cliente" devolve a
//     que era para informação. Com coluna "cliente" e sem "sim, todas", a
//     leitura traz a pergunta "Quais destes querem dizer cliente?"
//     (demo/trazerValores.js), já na resposta da troca: o servidor conta os
//     valores pelas linhas que leu, sem ler a planilha de novo. A resposta
//     dela vale para aquela coluna: trocar a coluna apaga a escolha. Ninguém é
//     cliente por causa do texto da célula: só pelo que a pessoa marcou.
// `trocaRele` e `respostaRele` dizem quando o servidor leria a planilha de
// novo (a coluna entra num alvo, sai de um, ou volta de "não guardar"): aí a
// fonte devolve o marcador `lendo` (fonte/trazerFonteDemo.js). A demonstração
// não lê nada de novo: os números e as linhas ficam os mesmos.
import { colunaPeloIndice } from '../fonte/trazerTraducao';
import { DESTINOS, LISTA_DE_DESTINOS, aparado } from '../trazer/destinos';
import { LIMITES } from '../trazer/limites';
import {
  PERGUNTA_CLIENTES,
  PERGUNTA_TELEFONE,
  PERGUNTA_VALORES,
  RESPOSTA_ALGUMAS,
} from '../trazer/respostas';
import { comAsContas, semAviso } from './trazerLinhas';
import { EXEMPLOS } from './trazerPlanilha';
import { recusa, valorInvalido } from './trazerRecusa';
import {
  comOsValores,
  exemploEhCliente,
  indiceDaColunaDeCliente,
  perguntaDosValores,
} from './trazerValores';

const ALVOS = [
  DESTINOS.NOME,
  DESTINOS.TELEFONE,
  DESTINOS.EMAIL,
  DESTINOS.EMPRESA,
];
const CONTATOS = [DESTINOS.TELEFONE, DESTINOS.EMAIL];
const SIM_TODAS = 'sim_todas';
const RESPOSTAS_DE_CLIENTES = [SIM_TODAS, 'ainda_nao', RESPOSTA_ALGUMAS];
const DA_PESSOA = 'da_pessoa';
// A resposta => o destino em que ela põe a coluna.
const DESTINO_DO_TELEFONE = {
  [DA_PESSOA]: DESTINOS.TELEFONE,
  da_empresa: DESTINOS.TELEFONE_DA_EMPRESA,
  nao_usar: DESTINOS.NAO_GUARDAR,
};

const alvoDe = destino => (ALVOS.includes(destino) ? destino : null);
const temDestino = (colunas, destino) =>
  colunas.some(coluna => coluna.destino === destino);
const semDuvida = ({ duvidosa, ...coluna }) => coluna;

// A coluna como o servidor a manda: só a informação leva o campo, que sem nome
// escrito fica com o título da coluna.
const colunaCom = ({ indice, nome }, destino, campo) =>
  destino === DESTINOS.INFORMACAO
    ? {
        indice,
        nome,
        destino,
        campo: {
          nome: aparado(campo?.nome) || nome,
          para_que_serve: aparado(campo?.para_que_serve),
        },
      }
    : { indice, nome, destino };

// ---- trocar o destino de uma coluna ------------------------------------------

export const trocaRele = (leitura, indice, destino) => {
  const atual = colunaPeloIndice(leitura, indice).destino;
  return (
    alvoDe(atual) !== alvoDe(destino) ||
    (atual === DESTINOS.NAO_GUARDAR && destino !== DESTINOS.NAO_GUARDAR)
  );
};

const longoDemais = campo =>
  aparado(campo?.nome).length > LIMITES.NOME_DO_CAMPO ||
  aparado(campo?.para_que_serve).length > LIMITES.PARA_QUE_SERVE;

// A coluna pedida, depois de conferido o pedido como o servidor confere. O
// telefone da empresa conta as colunas como ficariam depois da troca: a
// própria coluna de empresa não serve.
const conferirATroca = (leitura, indice, destino, campo) => {
  const coluna = colunaPeloIndice(leitura, indice);
  if (!LISTA_DE_DESTINOS.includes(destino)) {
    throw recusa('destino_desconhecido');
  }
  const sobraEmpresa = leitura.colunas.some(
    outra => outra.destino === DESTINOS.EMPRESA && outra.indice !== indice
  );
  if (destino === DESTINOS.TELEFONE_DA_EMPRESA && !sobraEmpresa) {
    throw recusa('sem_empresa');
  }
  if (longoDemais(campo)) throw valorInvalido('muito_longo');
  return coluna;
};

// Cada alvo é de uma coluna só, e só uma coluna diz quem é cliente.
const ehDeUmaColunaSo = destino =>
  alvoDe(destino) !== null || destino === DESTINOS.CLIENTE;

// A coluna pedida vai para o destino (a informação que já tinha campo fica com
// ele, se nenhum veio); a que estava no alvo (ou era "cliente") sai dele; e,
// sem coluna de empresa, a que era telefone da empresa volta a ser informação.
const colunasDepois = (colunas, indice, destino, campo) => {
  const trocadas = colunas.map(coluna => {
    if (coluna.indice === indice) {
      return colunaCom(coluna, destino, campo ?? coluna.campo);
    }
    return ehDeUmaColunaSo(destino) && coluna.destino === destino
      ? colunaCom(coluna, DESTINOS.INFORMACAO)
      : coluna;
  });
  return temDestino(trocadas, DESTINOS.EMPRESA)
    ? trocadas
    : trocadas.map(coluna =>
        coluna.destino === DESTINOS.TELEFONE_DA_EMPRESA
          ? colunaCom(coluna, DESTINOS.INFORMACAO)
          : coluna
      );
};

// A leitura com a coluna trocada (as perguntas e as respostas ainda são as de
// antes). A coluna que já é o alvo pedido fica como está. Na troca que faz ler
// de novo, as colunas passam a ser escolha da pessoa: nenhuma é mais duvidosa.
const comATroca = (leitura, indice, destino, campo) => {
  const coluna = conferirATroca(leitura, indice, destino, campo);
  if (alvoDe(destino) && coluna.destino === destino) return leitura;
  const colunas = colunasDepois(leitura.colunas, indice, destino, campo);
  if (!CONTATOS.some(contato => temDestino(colunas, contato))) {
    throw recusa('sem_contato');
  }
  return {
    ...leitura,
    colunas: trocaRele(leitura, indice, destino)
      ? colunas.map(semDuvida)
      : colunas,
  };
};

// ---- as perguntas, as respostas e os exemplos, como as colunas estão ---------

const perguntaDoTelefone = leitura =>
  leitura.perguntas.find(pergunta => pergunta.id === PERGUNTA_TELEFONE);

// A resposta do telefone vale enquanto a coluna está onde ela a pôs.
const telefoneRespondido = leitura => {
  const pergunta = perguntaDoTelefone(leitura);
  const resposta = leitura.respostas.telefone;
  if (!pergunta || !resposta) return false;
  const coluna = colunaPeloIndice(leitura, pergunta.indice);
  return coluna.destino === DESTINO_DO_TELEFONE[resposta];
};

const telefoneDuvidoso = leitura => {
  const pergunta = perguntaDoTelefone(leitura);
  if (!pergunta) return false;
  const coluna = colunaPeloIndice(leitura, pergunta.indice);
  return coluna.destino === DESTINOS.TELEFONE && coluna.duvidosa === true;
};

// Na ordem: "São clientes?", quais valores querem dizer cliente (quando há
// coluna de cliente) e o telefone (enquanto a pergunta dele existe).
// `respostas` são as que valem agora; o telefone é conferido como estava.
const perguntasDe = (leitura, respostas) => {
  const temTelefone = telefoneRespondido(leitura) || telefoneDuvidoso(leitura);
  return [
    { id: PERGUNTA_CLIENTES },
    perguntaDosValores({ colunas: leitura.colunas, respostas }),
    temTelefone ? perguntaDoTelefone(leitura) : null,
  ].filter(Boolean);
};

const respostaDeClientes = ({ colunas, respostas }) => {
  if (respostas.clientes === SIM_TODAS) return { clientes: SIM_TODAS };
  const marcadas = colunas
    .filter(coluna => coluna.destino === DESTINOS.CLIENTE)
    .map(coluna => coluna.indice);
  if (marcadas.length) {
    return {
      clientes: RESPOSTA_ALGUMAS,
      colunaCliente: marcadas.includes(respostas.colunaCliente)
        ? respostas.colunaCliente
        : marcadas[0],
    };
  }
  const vale = respostas.clientes && respostas.clientes !== RESPOSTA_ALGUMAS;
  return vale ? { clientes: respostas.clientes } : {};
};

// Os valores marcados valem enquanto a coluna que diz quem é cliente é a mesma
// para a qual foram marcados.
const valoresQueValem = (leitura, deClientes) => {
  const marcados = leitura.respostas[PERGUNTA_VALORES];
  const mesmaColuna =
    deClientes.colunaCliente !== undefined &&
    deClientes.colunaCliente === leitura.respostas.colunaCliente;
  return mesmaColuna && marcados ? { [PERGUNTA_VALORES]: marcados } : {};
};

const respostasDe = leitura => {
  const deClientes = respostaDeClientes(leitura);
  return {
    ...deClientes,
    ...valoresQueValem(leitura, deClientes),
    ...(telefoneRespondido(leitura)
      ? { telefone: leitura.respostas.telefone }
      : {}),
  };
};

// Cada exemplo entra como cliente com "sim, todas" ou quando a pessoa marcou,
// na coluna que diz quem é cliente, o que a planilha tem escrito para ele.
export const exemplosDe = (colunas, respostas) =>
  EXEMPLOS.map(({ celulas, ...exemplo }) => ({
    ...exemplo,
    cliente: exemploEhCliente({ colunas, respostas }, celulas),
  }));

// A escrita deu certo: o aviso de uma mudança desfeita some, e o resto da
// leitura (as perguntas, as respostas, os exemplos e as contas) acompanha as
// colunas.
const acertada = leitura => {
  const respostas = respostasDe(leitura);
  return comAsContas({
    ...semAviso(leitura),
    temEmpresa: temDestino(leitura.colunas, DESTINOS.EMPRESA),
    perguntas: perguntasDe(leitura, respostas),
    respostas,
    exemplos: exemplosDe(leitura.colunas, respostas),
  });
};

// `campo` só vem com a informação nova: `{ nome, para_que_serve }`.
export const aplicarDestino = (leitura, indice, destino, campo) =>
  acertada(comATroca(leitura, indice, destino, campo));

// ---- responder às perguntas ----------------------------------------------------

const conhecida = (resposta, conhecidas) =>
  resposta === undefined || conhecidas.includes(resposta);

// A coluna que diz quem é cliente não pode ser uma das que acham a pessoa.
const podeSerCliente = (leitura, indice) =>
  leitura.colunas.some(
    coluna => coluna.indice === indice && alvoDe(coluna.destino) === null
  );

const conferirAsRespostas = (
  leitura,
  { clientes, colunaCliente, telefone }
) => {
  const conhecidas =
    conhecida(clientes, RESPOSTAS_DE_CLIENTES) &&
    conhecida(telefone, Object.keys(DESTINO_DO_TELEFONE));
  if (!conhecidas) throw recusa('resposta_desconhecida');
  if (
    clientes === RESPOSTA_ALGUMAS &&
    !podeSerCliente(leitura, colunaCliente)
  ) {
    throw recusa('coluna_desconhecida');
  }
  if (telefone && !perguntaDoTelefone(leitura)) {
    throw recusa('pergunta_desconhecida');
  }
};

// É a mesma troca de destino da coluna, com as mesmas recusas. "É da pessoa"
// tira a dúvida da coluna.
const comOTelefone = (leitura, resposta) => {
  const { indice } = perguntaDoTelefone(leitura);
  const trocada = comATroca(leitura, indice, DESTINO_DO_TELEFONE[resposta]);
  return {
    ...trocada,
    colunas: trocada.colunas.map(coluna =>
      coluna.indice === indice ? semDuvida(coluna) : coluna
    ),
    respostas: { ...trocada.respostas, telefone: resposta },
  };
};

const semOsValores = respostas =>
  Object.fromEntries(
    Object.entries(respostas).filter(([chave]) => chave !== PERGUNTA_VALORES)
  );

// A coluna que era "cliente" volta a ser informação; com "algumas", a escolhida
// vira "cliente". Os valores marcados eram os da coluna de antes: com outra
// coluna (ou sem nenhuma), a escolha é apagada.
const comOsClientes = (leitura, { clientes, colunaCliente }) => {
  const escolhida = clientes === RESPOSTA_ALGUMAS ? colunaCliente : null;
  const colunas = leitura.colunas.map(coluna => {
    if (coluna.indice === escolhida) return colunaCom(coluna, DESTINOS.CLIENTE);
    return coluna.destino === DESTINOS.CLIENTE
      ? colunaCom(coluna, DESTINOS.INFORMACAO)
      : coluna;
  });
  const { colunaCliente: deAntes, ...todas } = leitura.respostas;
  const outras = escolhida === (deAntes ?? null) ? todas : semOsValores(todas);
  const respostas =
    escolhida === null
      ? { ...outras, clientes }
      : { ...outras, clientes, colunaCliente: escolhida };
  return { ...leitura, colunas, respostas };
};

// `respostas` é o que a tela tem: `{ clientes, colunaCliente, valores_cliente,
// telefone }`. Os valores valem para a coluna como o pedido a deixa, mas as
// chaves só são conhecidas para a coluna que já dizia quem é cliente antes
// dele. A recusa não deixa nada do pedido guardado.
export const aplicarRespostas = (leitura, respostas) => {
  conferirAsRespostas(leitura, respostas);
  const comTelefone = respostas.telefone
    ? comOTelefone(leitura, respostas.telefone)
    : leitura;
  const comClientes = respostas.clientes
    ? comOsClientes(comTelefone, respostas)
    : comTelefone;
  return acertada(
    comOsValores(
      comClientes,
      respostas[PERGUNTA_VALORES],
      indiceDaColunaDeCliente(leitura.colunas)
    )
  );
};

export const respostaRele = (
  leitura,
  { clientes, colunaCliente, telefone }
) => {
  const pergunta = perguntaDoTelefone(leitura);
  const oTelefoneRele =
    Boolean(telefone && pergunta) &&
    trocaRele(leitura, pergunta.indice, DESTINO_DO_TELEFONE[telefone]);
  return (
    oTelefoneRele ||
    (clientes === RESPOSTA_ALGUMAS &&
      trocaRele(leitura, colunaCliente, DESTINOS.CLIENTE))
  );
};
