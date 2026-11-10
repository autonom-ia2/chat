// #2414 F5 — operações sobre a receita da Automação livre (a árvore de passos,
// no formato de lib/operator_guide/automacao-receita.schema.json). Tudo devolve
// uma cópia nova: a versão salva é imutável, e o editor só troca a referência.
// O que o editor não conhece (um passo que só o Guia monta) passa intacto.

export const copiar = valor => JSON.parse(JSON.stringify(valor));

// Os galhos fixos de cada tipo de passo, na ordem em que aparecem. O
// "decidir" (F7, #2500) abre ainda um galho por caminho, antes do "nenhum".
export const RAMOS = {
  se: ['entao', 'senao'],
  esperar_ate: ['se_vencer', 'a_cada_mensagem'],
  decidir: ['nenhum'],
  // G18 (#2671): os passos que rodam no outro registro.
  em_outro_registro: ['passos'],
  // G13 (#2670): o que fazer quando o outro sistema recusa.
  webhook: ['se_recusar'],
};

// G63 (#2830): o galho do "esperar até" que roda a cada mensagem do cliente
// enquanto espera e, no fim, volta à mesma espera. G64 (#2839): sem prazo, a
// hora cheia da conferência diária (no fuso da conta); nasce às 8h (decisão
// 12 do Rodrigo, 09/11).
export const A_CADA = 'a_cada_mensagem';
export const HORA_DA_CONFERENCIA = 8;

// #2750: o "esperar até" sem prazo só termina pela condição (o esquema:
// `prazo_da_espera`). Não vence, então não tem "se o prazo acabar".
export const SEM_PRAZO = 'sem_prazo';
const semSeVencer = passo =>
  passo.tipo === 'esperar_ate' &&
  passo.prazo === SEM_PRAZO &&
  !passo.se_vencer?.length;

// Lista raiz: 'raiz'. Lista de um galho: '<id do passo>:<ramo>'.
export const RAIZ = 'raiz';
export const idDaLista = (passoId, ramo) => `${passoId}:${ramo}`;

const galhoFixo = (passo, ramo) => ({
  ramo,
  passos: passo[ramo],
  com: (alvo, lista) => ({ ...alvo, [ramo]: lista }),
});

const galhoDoCaminho = (caminho, indice) => ({
  ramo: `caminhos.${indice}`,
  nome: caminho.nome,
  passos: caminho.passos,
  com: (alvo, lista) => ({
    ...alvo,
    caminhos: alvo.caminhos.map((outro, i) =>
      i === indice ? { ...outro, passos: lista } : outro
    ),
  }),
});

// Os galhos de um passo, na ordem em que aparecem: `ramo` (o fim do id da
// lista), `passos` (pode faltar), `nome` (o do caminho) e `com(passo, lista)`,
// que devolve o passo com o galho trocado. É a única travessia da árvore no
// editor; o servidor tem a sua em Autonomia::Automacao::Receita.ramos.
export const galhosDe = passo => {
  const fixos = (RAMOS[passo.tipo] || []).filter(
    ramo => ramo !== 'se_vencer' || !semSeVencer(passo)
  );
  return [
    ...fixos.filter(ramo => ramo !== 'nenhum').map(r => galhoFixo(passo, r)),
    ...(passo.caminhos || []).map((caminho, i) =>
      galhoDoCaminho(caminho || {}, i)
    ),
    ...fixos.filter(ramo => ramo === 'nenhum').map(r => galhoFixo(passo, r)),
  ];
};

// Aplica `fn` em toda lista da árvore; `fn(lista, listaId)` devolve a nova. O
// galho opcional que não existe ("senão" sem passo) só aparece na receita se
// ganhou passo: a receita que ninguém mexeu volta igual.
const mapearListas = (passos, fn, listaId = RAIZ) =>
  fn(passos, listaId).map(passo =>
    galhosDe(passo).reduce((novo, galho) => {
      const lista = mapearListas(
        galho.passos || [],
        fn,
        idDaLista(passo.id, galho.ramo)
      );
      if (!Array.isArray(galho.passos) && !lista.length) return novo;
      return galho.com(novo, lista);
    }, passo)
  );

export const inserirPasso = (passos, listaId, indice, novo) =>
  mapearListas(passos, (lista, id) =>
    id === listaId
      ? [...lista.slice(0, indice), novo, ...lista.slice(indice)]
      : lista
  );

export const trocarPasso = (passos, novo) =>
  mapearListas(passos, lista =>
    lista.map(passo => (passo.id === novo.id ? novo : passo))
  );

// Tirar um passo de um galho obrigatório ("então" do "se") pode deixar o galho
// vazio; a receita volta recusada ao salvar, com a frase, e a pessoa corrige.
export const tirarPasso = (passos, id) =>
  mapearListas(passos, lista => lista.filter(passo => passo.id !== id));

export const todosOsPassos = (passos = []) =>
  passos.flatMap(passo => [
    passo,
    ...galhosDe(passo).flatMap(galho => todosOsPassos(galho.passos || [])),
  ]);

// G18: os passos que rodam na mesma execução: o ramo do "em outro registro"
// roda numa execução filha, no registro ligado.
export const OUTRO_REGISTRO = 'em_outro_registro';
export const naMesmaExecucao = (passos = []) =>
  passos.flatMap(passo => [
    passo,
    ...(passo.tipo === OUTRO_REGISTRO
      ? []
      : galhosDe(passo).flatMap(galho => naMesmaExecucao(galho.passos || []))),
  ]);

export const acharPasso = (passos, id) =>
  todosOsPassos(passos).find(passo => passo.id === id) || null;

// O passo `id` está dentro do galho "a cada mensagem" de algum "esperar até"
// (em qualquer nível)? Ele roda uma vez por mensagem do cliente.
export const noGalhoACada = (passos, id) =>
  todosOsPassos(passos).some(
    passo =>
      passo.tipo === 'esperar_ate' &&
      todosOsPassos(passo[A_CADA] || []).some(dentro => dentro.id === id)
  );

// Id curto e único na receita: o cursor da execução aponta para ele.
export const novoId = passos => {
  const usados = new Set(todosOsPassos(passos).map(passo => passo.id));
  let numero = usados.size + 1;
  while (usados.has(`p${numero}`)) numero += 1;
  return `p${numero}`;
};

export const receitaVazia = () => ({ gatilho: null, passos: [] });

// G18: o "em outro registro" diz onde rodar. O contato do campo pede o campo;
// os cards do contato valem sem filtro.
export const registroPronto = registro => {
  if (registro?.de === 'cards_do_contato') return true;
  if (registro?.de === 'criado_no_passo') return Boolean(registro.passo);
  return registro?.de === 'contato_do_campo' && Boolean(registro.campo?.$valor);
};

// "Se" e "Esperar até" nascem sem condição, e o "Se" sem passo em "Então"; o
// "Em outro registro" (G18), sem passo dentro: o esquema recusa até a pessoa
// completar pelo próprio Confira.
const incompleto = passo => {
  if (passo.tipo === 'em_outro_registro')
    return !passo.passos?.length || !registroPronto(passo.registro);
  return (
    (passo.tipo === 'se' || passo.tipo === 'esperar_ate') &&
    (!passo.condicao || (passo.tipo === 'se' && !passo.entao?.length))
  );
};

// Pronta para salvar: o esquema pede gatilho, pelo menos um passo e cada "Se"
// e "Esperar até" completos.
export const falta = receita => {
  if (!receita?.gatilho?.tipo) return 'GATILHO';
  if (!receita.passos?.length) return 'PASSO';
  if (todosOsPassos(receita.passos).some(incompleto)) return 'COMPLETAR';
  return null;
};

// A receita da tela é a salva? Compara o conteúdo, não a ordem das chaves: o
// passo que a pessoa abriu e salvou sem mudar nada não vira "mudança".
export const iguais = (a, b) => {
  if (a === b) return true;
  if (Array.isArray(a) || Array.isArray(b))
    return (
      Array.isArray(a) &&
      Array.isArray(b) &&
      a.length === b.length &&
      a.every((item, i) => iguais(item, b[i]))
    );
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object') return false;
  const chaves = Object.keys(a);
  return (
    chaves.length === Object.keys(b).length &&
    chaves.every(chave => iguais(a[chave], b[chave]))
  );
};

// #2496 — o valor da mensagem só existe no "Só se" do gatilho dela. Trocar o
// gatilho tira a condição que deixou de valer e, no gatilho que sugere uma, já
// põe a sugestão quando o "Só se" ainda não olha a mensagem. O painel mostra o
// que entra e o que sai antes do "Salvar".
const caminhosDa = condicao =>
  condicao?.todas || condicao?.alguma
    ? (condicao.todas || condicao.alguma).flatMap(caminhosDa)
    : [condicao?.campo?.$valor];

export const filtrosDoGatilho = (filtros, tipo, catalogo) => {
  const doGatilho = (catalogo?.valores || []).filter(
    item => item.so_no_gatilho
  );
  const vale = caminho =>
    doGatilho.every(
      item => item.caminho !== caminho || item.so_no_gatilho === tipo
    );
  const todos = filtros || [];
  const ficam = todos.filter(filtro => caminhosDa(filtro).every(vale));
  const saem = todos.filter(filtro => !ficam.includes(filtro));
  const sugerido = catalogo?.gatilhos.find(
    item => item.tipo === tipo
  )?.filtro_sugerido;
  const olhaAMensagem = ficam.some(filtro =>
    caminhosDa(filtro).some(caminho =>
      doGatilho.some(item => item.caminho === caminho)
    )
  );
  const entra = sugerido && !olhaAMensagem ? copiar(sugerido) : null;
  return { filtros: entra ? [...ficam, entra] : ficam, entra, saem };
};
