// #2486 — o texto de "mensagem" e "avisar" na tela. A receita guarda pedaços
// (`["Oi ", {"$valor": "contato.nome"}]`); a pessoa vê e escreve uma frase só,
// com cada dado entre colchetes: "Oi [Nome do contato]". O colchete só vira
// dado quando o nome bate, letra por letra, com um dado da lista; o resto fica
// como texto. O campo personalizado que a conta apagou continua dado, marcado
// como apagado: virar texto mandaria "[Placa]" ao cliente, e o salvar o recusa
// (atributo_inexistente) até a pessoa tirar ou trocar.

const ABRE = '[';
const FECHA = ']';

// Os dados que o motor lê do alvo, com o nome que a tela mostra. O campo
// personalizado entra pelo nome que a conta deu a ele; dois campos com o mesmo
// nome levam a chave junto, senão o rótulo não diria qual dos dois é.
const comChaveSeRepetido = opcoes => {
  const vezes = opcoes.reduce(
    (conta, item) => ({ ...conta, [item.label]: (conta[item.label] || 0) + 1 }),
    {}
  );
  return opcoes.map(({ chave, ...item }) =>
    vezes[item.label] > 1 && chave
      ? { ...item, label: `${item.label} (${chave})` }
      : item
  );
};

// O nome do valor no catálogo. O do registro de origem (G65, `origem`) leva a
// marca, para não confundir com o mesmo valor do registro em que o ramo roda.
export const nomeDoValor = (item, t) =>
  item.origem
    ? t('AUTOMACAO_LIVRE.OUTRO_REGISTRO.DA_ORIGEM', { valor: t(item.frase) })
    : t(item.frase);

// O valor da mensagem (#2496) só aparece no "Só se" do gatilho dela; no texto
// e nos passos, `gatilho` não vem e ele fica de fora. O que só o Guia monta
// (`so_guia`) e o que a pessoa não pode ler (`sem_permissao`, #2597) nunca
// entram na escolha. A resposta durante a espera (G11, `so_na_espera`) só
// aparece na condição do "esperar até" (`naEspera`).
export const opcoesDosValores = (
  catalogo,
  atributosDo,
  t,
  gatilho = null,
  naEspera = false
) =>
  comChaveSeRepetido(
    (catalogo?.valores || []).flatMap(item => {
      if (item.so_guia || item.sem_permissao) return [];
      if (item.so_no_gatilho && item.so_no_gatilho !== gatilho) return [];
      if (item.so_na_espera && !naEspera) return [];
      // G53: a mensagem que falhou (`so_nos_passos`) não entra no "Só se" do
      // gatilho: o filtro roda antes de ela ser lida.
      if (item.so_nos_passos && gatilho) return [];
      // #2679: o texto da IA já chega com o rótulo pronto (comTextosDaIa). No
      // "Só se" do gatilho nenhum passo rodou: ele não entra.
      if (item.rotulo && gatilho) return [];
      if (item.rotulo)
        return [{ value: item.caminho, chave: item.chave, label: item.rotulo }];
      if (!item.atributos)
        return [{ value: item.caminho, label: nomeDoValor(item, t) }];
      return atributosDo(item.atributos).map(atributo => ({
        value: `${item.caminho}.${atributo.attribute_key}`,
        chave: atributo.attribute_key,
        label: t('AUTOMACAO_LIVRE.FRASES.ATRIBUTO', {
          base: nomeDoValor(item, t),
          chave: atributo.attribute_display_name,
        }),
      }));
    })
  );

// #2414 G16 — o campo de texto de uma ação. Só texto fica string; com dado,
// vira `{ $texto: [...] }`, montado na hora da execução (o motor pula a ação se
// o dado estiver vazio).
export const partesDoCampo = valor => {
  if (valor?.$texto) return valor.$texto;
  if (valor?.$valor) return [valor];
  return valor === undefined || valor === null || valor === ''
    ? []
    : [String(valor)];
};

export const campoDasPartes = partes =>
  (partes || []).some(parte => typeof parte !== 'string')
    ? { $texto: partes }
    : (partes || []).join('');

// #2414 G16b — os campos de data que a data calculada pode usar como ponto de
// partida: só os atributos do tipo data, com os rótulos do "Pôr um dado".
export const opcoesDeDatas = (catalogo, atributosDo, t) => {
  const bases = (catalogo?.valores || []).filter(item => item.atributos);
  return opcoesDosValores(
    { ...catalogo, valores: bases },
    modelo =>
      atributosDo(modelo).filter(
        atributo => atributo.attribute_display_type === 'date'
      ),
    t
  );
};

// O mesmo teto do esquema (automacao-receita.schema.json), contra erro de
// digitação.
export const TETO_DA_DATA = 3650;

// A data calculada só vai para a receita inteira: o ponto de partida escolhido
// e, quando há "mais", um número inteiro dentro do teto.
export const dataCompleta = data =>
  Boolean(data?.de) &&
  (data.mais === undefined ||
    (Number.isInteger(data.mais.valor) &&
      Math.abs(data.mais.valor) <= TETO_DA_DATA));

export const temDataIncompleta = valor => {
  if (!valor || typeof valor !== 'object') return false;
  if (valor.$data) return !dataCompleta(valor.$data);
  return Object.values(valor).some(temDataIncompleta);
};

// O valor que a pessoa não pode ler (#2597) e que o texto já usa, com o nome
// dele: mostra o nome, não "apagado". Só o que já está nas partes entra, para
// digitar o nome entre colchetes não criar o dado.
export const valoresSemPermissao = (catalogo, t, partes = []) => {
  const usados = partes
    .filter(parte => typeof parte !== 'string')
    .map(parte => parte.$valor);
  return (catalogo?.valores || [])
    .filter(item => item.sem_permissao && usados.includes(item.caminho))
    .map(item => ({ value: item.caminho, label: nomeDoValor(item, t) }));
};

export const comColchetes = rotulo => `${ABRE}${rotulo}${FECHA}`;

// Os dados do texto que não estão mais entre as opções (o campo apagado)
// entram como opção marcada `apagado`, com o rótulo que `rotular(caminho)` dá:
// assim voltam ao mesmo {$valor} na ida e volta.
export const comApagados = (partes, opcoes, rotular) => {
  const sobrando = (partes || [])
    .filter(parte => typeof parte !== 'string')
    .map(parte => parte.$valor)
    .filter(
      (caminho, i, todos) =>
        todos.indexOf(caminho) === i &&
        !opcoes.some(item => item.value === caminho)
    );
  return [
    ...opcoes,
    ...sobrando.map(caminho => ({
      value: caminho,
      label: rotular(caminho),
      apagado: true,
    })),
  ];
};

export const textoNaTela = (partes, opcoes) =>
  (partes || [])
    .map(parte => {
      if (typeof parte === 'string') return parte;
      const opcao = opcoes.find(item => item.value === parte.$valor);
      return comColchetes(opcao ? opcao.label : parte.$valor);
    })
    .join('');

const juntar = (partes, pedaco) => {
  if (!pedaco) return partes;
  if (typeof pedaco !== 'string' || typeof partes.at(-1) !== 'string')
    return [...partes, pedaco];
  return [...partes.slice(0, -1), partes.at(-1) + pedaco];
};

// Cada "[" pode abrir um dado: vale o rótulo inteiro, "[" + nome + "]", que
// bate com uma opção (o nome pode ter colchete, como "Valor [R$]"). Sem
// opção que bata, o "[" fica como texto.
const dadoEm = (texto, ponto, opcoes) =>
  opcoes
    .filter(item => texto.startsWith(comColchetes(item.label), ponto))
    .sort((a, b) => b.label.length - a.label.length)[0] || null;

export const textoDaTela = (texto, opcoes) => {
  const tudo = texto || '';
  let partes = [];
  let inicio = 0;
  let ponto = tudo.indexOf(ABRE);
  while (ponto >= 0) {
    const opcao = dadoEm(tudo, ponto, opcoes);
    if (opcao) {
      partes = juntar(juntar(partes, tudo.slice(inicio, ponto)), {
        $valor: opcao.value,
      });
      inicio = ponto + comColchetes(opcao.label).length;
      ponto = tudo.indexOf(ABRE, inicio);
    } else ponto = tudo.indexOf(ABRE, ponto + 1);
  }
  return juntar(partes, tudo.slice(inicio));
};
