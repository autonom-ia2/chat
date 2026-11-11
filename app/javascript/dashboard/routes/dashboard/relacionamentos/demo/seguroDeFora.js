// #2897 — o seguro que a pessoa tem em outra corretora (Tela 20): os arquivos
// fictícios que "vieram na conversa" e o que a leitura de cada um devolve. Só é
// carregado no ambiente de desenvolvimento, junto com demo/carteira.js. Nada é
// lido de verdade: cada arquivo de exemplo cai num estado da tela.
import { SEGURADORA_DA_PLANILHA } from './carteiraPlano';
import { DIA_EM_MS } from '../fonte/grupos';

const SEGUNDOS_POR_DIA = DIA_EM_MS / 1000;
const MS_POR_SEGUNDO = 1000;
// O seguro de exemplo termina daqui a pouco mais de três meses.
const TERMINA_EM_DIAS = 101;

const APOLICE = 'apolice-auto.pdf';
const FOTO_ESCURA = 'foto-da-apolice.jpg';
const NAO_E_SEGURO = 'foto-do-carro.jpg';
const SEM_DATA = 'apolice-sem-data.pdf';

export const arquivosDeExemplo = () =>
  [APOLICE, FOTO_ESCURA, NAO_E_SEGURO, SEM_DATA].map(nome => ({ nome }));

const erroComNome = (name, mensagem) =>
  Object.assign(new Error(mensagem), { name });

const FALHAS = {
  [FOTO_ESCURA]: () => erroComNome('FOTO_ESCURA', 'A foto está escura demais.'),
  [NAO_E_SEGURO]: () =>
    erroComNome('NAO_PARECE_SEGURO', 'Este arquivo não parece um seguro.'),
};

// O que foi lido: tipo, seguradora e quando termina (em segundos; `null` é o
// que a leitura não achou).
export const lerDeFora = (arquivo, agora = Date.now()) => {
  const nome = String(arquivo?.nome ?? '');
  if (FALHAS[nome]) throw FALHAS[nome]();
  return {
    arquivo: nome,
    tipo: 'auto',
    seguradora: SEGURADORA_DA_PLANILHA,
    termina:
      nome === SEM_DATA
        ? null
        : Math.floor(agora / MS_POR_SEGUNDO) +
          TERMINA_EM_DIAS * SEGUNDOS_POR_DIA,
  };
};
