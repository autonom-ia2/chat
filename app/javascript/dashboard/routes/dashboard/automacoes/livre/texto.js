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

// O valor da mensagem (#2496) só aparece no "Só se" do gatilho dela; no texto
// e nos passos, `gatilho` não vem e ele fica de fora. O que só o Guia monta
// (`so_guia`) nunca entra na escolha.
export const opcoesDosValores = (catalogo, atributosDo, t, gatilho = null) =>
  comChaveSeRepetido(
    (catalogo?.valores || []).flatMap(item => {
      if (item.so_guia) return [];
      if (item.so_no_gatilho && item.so_no_gatilho !== gatilho) return [];
      if (!item.atributos)
        return [{ value: item.caminho, label: t(item.frase) }];
      return atributosDo(item.atributos).map(atributo => ({
        value: `${item.caminho}.${atributo.attribute_key}`,
        chave: atributo.attribute_key,
        label: t('AUTOMACAO_LIVRE.FRASES.ATRIBUTO', {
          base: t(item.frase),
          chave: atributo.attribute_display_name,
        }),
      }));
    })
  );

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
