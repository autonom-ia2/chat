// #2900 (E7.3) — de onde "Trazer do Agger" lê e para onde escreve: a busca e o
// interruptor (api/relacionamentosTrazerAgger.js), o Conferir, trazer, o
// andamento e o desfazer das leituras (api/relacionamentosTrazerPdfs.js) e o
// login do Agger, que é a conexão da Cotação (api/autonomiaInsurance.js, uma
// só por conta). As recusas ganham nome como no resto da carteira
// (fonte/carteiraFonteReal.js). A senha só vai no pedido de conectar e nunca
// volta. A demonstração não tem o Agger: a porta nem mostra o caminho.
import AggerAPI from 'dashboard/api/relacionamentosTrazerAgger';
import PdfsAPI from 'dashboard/api/relacionamentosTrazerPdfs';
import AutonomiaInsuranceAPI from 'dashboard/api/autonomiaInsurance';
import { LOGIN } from '../carteira/useBuscaNoAgger';
import { noServidor } from './carteiraFonteReal';

// O login deu certo: a conexão está pronta ou varrendo os produtos da Cotação
// (a carteira não espera a varredura; Carteira::Conector.pronta?).
const LOGIN_ACEITO = ['ready', 'discovering'];
// O Agger não respondeu como devia (fora do ar, lento, pedindo alguém, ainda
// entrando): não é o login e a senha que estão errados.
const AGGER_FORA_DO_AR = [
  'degraded',
  'offline',
  'human_required',
  'provisioning',
  'authenticating',
];

const respostaDoLogin = status => {
  if (LOGIN_ACEITO.includes(status)) return LOGIN.ACEITO;
  return AGGER_FORA_DO_AR.includes(status) ? LOGIN.FORA_DO_AR : LOGIN.RECUSADO;
};

export const trazerAggerFonte = () => ({
  conectar: async ({ login, senha }) => {
    const resposta = await noServidor(() =>
      AutonomiaInsuranceAPI.connect({ username: login, password: senha })
    );
    return respostaDoLogin(resposta?.payload?.status);
  },
  buscar: () => noServidor(() => AggerAPI.buscar()),
  deNovo: id => noServidor(() => AggerAPI.deNovo(id)),
  busca: id => noServidor(() => PdfsAPI.lote(id)),
  trazer: id => noServidor(() => PdfsAPI.trazer(id)),
  andamento: id => noServidor(() => PdfsAPI.andamento(id)),
  historico: () => noServidor(() => AggerAPI.historico()),
  previaDoDesfazer: id => noServidor(() => PdfsAPI.previaDoDesfazer(id)),
  desfazer: id => noServidor(() => PdfsAPI.desfazer(id)),
  // { ligado, jaTrouxe }: o interruptor só aparece depois da primeira busca
  // trazida.
  buscaDiaria: async () => {
    const resposta = await noServidor(() => AggerAPI.buscaDiaria());
    return {
      ligado: resposta.ligado === true,
      jaTrouxe: resposta.jaTrouxe === true,
    };
  },
  mudarBuscaDiaria: async ligado => {
    const resposta = await noServidor(() => AggerAPI.mudarBuscaDiaria(ligado));
    return resposta.ligado === true;
  },
});
