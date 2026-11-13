import { DIA_EM_MS } from '../fonte/grupos';
import { pessoasDeExemplo } from '../lista/pessoasDeExemplo';

// #2897 — a lista de exemplo da conta sem seguro: cinco seguros inventados, das
// mesmas pessoas de exemplo da lista de pessoas, só para mostrar como a aba
// fica quando a carteira tem seguros. Nada aqui existe: as seguradoras são nomes
// inventados. `dias` é em quantos dias o seguro termina.
const EXEMPLOS = [
  { tipo: 'auto', seguradora: 'Seguradora Atlântica', dias: 6 },
  { tipo: 'residencial', seguradora: 'Horizonte Seguros', dias: 21 },
  { tipo: 'vida', seguradora: 'Serra Azul Seguros', dias: 74 },
  { tipo: 'auto', seguradora: 'Horizonte Seguros', dias: 160 },
  { tipo: 'empresarial', seguradora: 'Seguradora Atlântica', dias: 290 },
];
const MS_EM_SEGUNDO = 1000;

export const segurosDeExemplo = (agora = Date.now()) => {
  const pessoas = pessoasDeExemplo(agora);
  return EXEMPLOS.map(({ tipo, seguradora, dias }, indice) => ({
    id: `exemplo-${indice + 1}`,
    tipo,
    seguradora,
    termina: Math.floor((agora + dias * DIA_EM_MS) / MS_EM_SEGUNDO),
    canceladoEm: null,
    segurado: { tipo: 'pessoa', nome: pessoas[indice].name },
  }));
};
