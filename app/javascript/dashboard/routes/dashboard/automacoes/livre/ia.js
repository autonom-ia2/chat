// #2500 F7 — os caminhos do "decidir". O caminho mostra o nome que a pessoa
// escreveu ("Cotação"); a chave, que a IA devolve e que nunca aparece na tela,
// sai dele: minúscula, sem acento, com _. As mesmas regras a Receita confere
// no servidor (caminho_repetido, caminho_reservado, caminho_sem_letra).
const LETRAS = 'abcdefghijklmnopqrstuvwxyz';
const DIGITOS = '0123456789';
// A chave do ramo "nenhum se aplica" (Receita::NENHUM).
const NENHUM = 'nenhum';

export const chaveDoNome = nome =>
  [...nome.normalize('NFD').toLowerCase()]
    .filter(
      letra =>
        LETRAS.includes(letra) || DIGITOS.includes(letra) || letra === ' '
    )
    .join('')
    .split(' ')
    .filter(Boolean)
    .join('_');

const nomeComparavel = caminho => (caminho.nome || '').trim().toLowerCase();

// O que impede o caminho de ser salvo, em uma palavra para o i18n; null quando
// está certo. Sem nome ainda não é problema: o painel só pede o nome.
export const problemaDoCaminho = (caminhos, indice) => {
  const caminho = caminhos[indice];
  if (!nomeComparavel(caminho)) return null;
  if (![...(caminho.chave || '')].some(letra => LETRAS.includes(letra)))
    return 'SEM_LETRA';
  if (caminho.chave === NENHUM) return 'RESERVADO';
  const repetido = caminhos.some(
    (outro, i) =>
      i !== indice &&
      (outro.chave === caminho.chave ||
        nomeComparavel(outro) === nomeComparavel(caminho))
  );
  return repetido ? 'REPETIDO' : null;
};

export const caminhosProntos = caminhos =>
  caminhos.length >= 2 &&
  caminhos.every(
    (caminho, indice) =>
      nomeComparavel(caminho) &&
      caminho.descricao?.trim() &&
      !problemaDoCaminho(caminhos, indice)
  );

// #2414 G31 — o "decidir" que espera a próxima resposta e decide de novo
// quando a IA escolhe um dos caminhos marcados. As mesmas regras a Receita
// confere no servidor (DecidirDeNovo): o caminho marcado não tem passos, e
// sobra pelo menos um caminho para a automação seguir.
export { NENHUM };

// Os nomes dos caminhos marcados que ainda têm passos ("nenhum" pelo galho
// dele), na ordem em que aparecem. Com "voltar a esperar" (G46), o caminho
// marcado roda os passos dele e volta: ter passos não é problema.
export const marcadosComPassos = passo => {
  if (passo.de_novo?.desde) return [];
  const marcados = passo.de_novo?.caminhos || [];
  const cheios = (passo.caminhos || [])
    .filter(caminho => marcados.includes(caminho.chave))
    .filter(caminho => (caminho.passos || []).length)
    .map(caminho => caminho.nome);
  return marcados.includes(NENHUM) && (passo.nenhum || []).length
    ? [...cheios, NENHUM]
    : cheios;
};

// A chave marcada que o passo não tem mais (o caminho foi renomeado ou tirado).
export const marcadosDesconhecidos = passo => {
  const chaves = [...(passo.caminhos || []).map(item => item.chave), NENHUM];
  return (passo.de_novo?.caminhos || []).filter(
    chave => !chaves.includes(chave)
  );
};

// Todas as saídas marcadas: os caminhos e o "nenhum", que também é saída.
export const todosMarcados = passo => {
  const marcados = passo.de_novo?.caminhos || [];
  const saidas = [...(passo.caminhos || []).map(item => item.chave), NENHUM];
  return saidas.every(chave => marcados.includes(chave));
};

// Desligado (sem `de_novo`) está pronto; ligado, pede um caminho marcado, o
// prazo ou o "voltar a esperar" e nenhum dos problemas acima.
const prazoPronto = prazo =>
  Number.isInteger(prazo?.valor) && Boolean(prazo?.unidade);
export const deNovoPronto = passo => {
  const deNovo = passo.de_novo;
  if (!deNovo) return true;
  return (
    (deNovo.caminhos || []).length > 0 &&
    (Boolean(deNovo.desde) || prazoPronto(deNovo.prazo)) &&
    !marcadosDesconhecidos(passo).length &&
    !marcadosComPassos(passo).length &&
    !todosMarcados(passo)
  );
};

// G46 — para onde o caminho marcado pode voltar: os "esperar até" que vêm
// antes do "decidir" `id`, na mesma lista, e esperam o cliente (a resposta ou
// a foto ou PDF, igual a sim). A mesma regra a Receita confere no servidor
// (DecidirDeNovo::Desde); o mais perto primeiro.
const DO_CLIENTE = [
  'conversa.cliente_respondeu',
  'conversa.cliente_mandou_documento',
];
export const esperaOCliente = condicao => {
  if (!condicao) return false;
  if (condicao.todas) return condicao.todas.some(esperaOCliente);
  if (condicao.alguma) return condicao.alguma.every(esperaOCliente);
  return (
    DO_CLIENTE.includes(condicao.campo?.$valor) &&
    condicao.op === 'igual' &&
    condicao.valor === true
  );
};

const ramosDoPasso = passo => [
  passo.entao,
  passo.senao,
  passo.se_vencer,
  ...(passo.caminhos || []).map(caminho => caminho.passos),
  passo.nenhum,
];

const listaCom = (lista, id) => {
  if (!Array.isArray(lista)) return null;
  if (lista.some(passo => passo.id === id)) return lista;
  return lista
    .flatMap(passo => ramosDoPasso(passo))
    .reduce((achada, ramo) => achada || listaCom(ramo, id), null);
};

export const esperasAnteriores = (receita, id) => {
  const lista = listaCom(receita?.passos, id) || [];
  const indice = lista.findIndex(passo => passo.id === id);
  return lista
    .slice(0, Math.max(indice, 0))
    .reverse()
    .filter(
      passo => passo.tipo === 'esperar_ate' && esperaOCliente(passo.condicao)
    );
};
