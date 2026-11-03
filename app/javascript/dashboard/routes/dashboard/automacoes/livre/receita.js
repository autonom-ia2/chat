// #2414 F5 — operações sobre a receita da Automação livre (a árvore de passos,
// no formato de lib/operator_guide/automacao-receita.schema.json). Tudo devolve
// uma cópia nova: a versão salva é imutável, e o editor só troca a referência.
// O que o editor não conhece (um passo que só o Guia monta) passa intacto.

export const copiar = valor => JSON.parse(JSON.stringify(valor));

// Os galhos de cada tipo de passo, na ordem em que aparecem.
export const RAMOS = { se: ['entao', 'senao'], esperar_ate: ['se_vencer'] };

// Lista raiz: 'raiz'. Lista de um galho: '<id do passo>:<ramo>'.
export const RAIZ = 'raiz';
export const idDaLista = (passoId, ramo) => `${passoId}:${ramo}`;

const ramosDe = passo => RAMOS[passo.tipo] || [];

// Aplica `fn` em toda lista da árvore; `fn(lista, listaId)` devolve a nova. O
// galho opcional que não existe ("senão" sem passo) só aparece na receita se
// ganhou passo: a receita que ninguém mexeu volta igual.
const mapearListas = (passos, fn, listaId = RAIZ) =>
  fn(passos, listaId).map(passo =>
    ramosDe(passo).reduce((novo, ramo) => {
      const lista = mapearListas(
        passo[ramo] || [],
        fn,
        idDaLista(passo.id, ramo)
      );
      if (!Array.isArray(passo[ramo]) && !lista.length) return novo;
      return { ...novo, [ramo]: lista };
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
    ...ramosDe(passo).flatMap(ramo => todosOsPassos(passo[ramo] || [])),
  ]);

export const acharPasso = (passos, id) =>
  todosOsPassos(passos).find(passo => passo.id === id) || null;

// Id curto e único na receita: o cursor da execução aponta para ele.
export const novoId = passos => {
  const usados = new Set(todosOsPassos(passos).map(passo => passo.id));
  let numero = usados.size + 1;
  while (usados.has(`p${numero}`)) numero += 1;
  return `p${numero}`;
};

export const receitaVazia = () => ({ gatilho: null, passos: [] });

// "Se" e "Esperar até" nascem sem condição, e o "Se" sem passo em "Então": o
// esquema recusa os dois até a pessoa completar pelo próprio Confira.
const incompleto = passo =>
  (passo.tipo === 'se' || passo.tipo === 'esperar_ate') &&
  (!passo.condicao || (passo.tipo === 'se' && !passo.entao?.length));

// Pronta para salvar: o esquema pede gatilho, pelo menos um passo e cada "Se"
// e "Esperar até" completos.
export const falta = receita => {
  if (!receita?.gatilho?.tipo) return 'GATILHO';
  if (!receita.passos?.length) return 'PASSO';
  if (todosOsPassos(receita.passos).some(incompleto)) return 'COMPLETAR';
  return null;
};
