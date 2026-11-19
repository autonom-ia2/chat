// #3078 — as empresas que esta aba do navegador acabou de apagar.
//
// Causa raiz: apagar empresa no servidor é um job (DELETE companies/:id
// responde na hora e Companies::DeleteJob apaga depois, na fila `low`). A lista
// relida logo em seguida ainda traz a empresa, e quem acabou de apagar a veria
// de volta. Mitigação: por alguns minutos a lista deixa de fora as empresas
// apagadas daqui (fonte/listaFonte.js), e o total desconta. O conserto
// definitivo é o servidor responder só depois de apagar, ou marcar a empresa
// como "saindo" para a consulta da lista não a ler. TODO(#3078): abrir a Issue
// desse conserto no servidor; enquanto ela não sai, fica esta mitigação.
const VALE_POR_MS = 5 * 60 * 1000;

let apagadas = new Map();

const vigentes = (agora = Date.now()) =>
  new Map([...apagadas].filter(([, quando]) => agora - quando < VALE_POR_MS));

export const lembrarApagada = (id, agora = Date.now()) => {
  apagadas = new Map([...vigentes(agora), [Number(id), agora]]);
};

export const foiApagada = (id, agora = Date.now()) =>
  vigentes(agora).has(Number(id));

// A página da lista sem as empresas apagadas daqui, com o total descontado.
export const semAsApagadas = (pagina, agora = Date.now()) => {
  const itens = pagina.itens.filter(empresa => !foiApagada(empresa.id, agora));
  const fora = pagina.itens.length - itens.length;
  return { ...pagina, itens, total: Math.max(0, pagina.total - fora) };
};

// Só para os testes.
export const esquecerApagadas = () => {
  apagadas = new Map();
};
