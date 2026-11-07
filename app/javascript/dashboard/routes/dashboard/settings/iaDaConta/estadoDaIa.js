// #2472: a frase do topo da tela sai das fontes conectadas. Ordem de uso:
// primeiro o login ChatGPT, depois a chave. Função pura, para o spec e para a
// faixa do painel usarem a mesma regra.
const USAVEL = 'funcionando';

export const estadoDaIa = ({ chatgpt, chave }) => {
  if (!chatgpt && !chave) return { tipo: 'vazio', texto: 'VAZIO_TEXTO' };

  const loginOk = chatgpt?.status === USAVEL;
  const chaveOk = chave?.status === USAVEL;

  if (loginOk && chaveOk) return { tipo: 'ok', texto: 'OK_OS_DOIS' };
  // Só o login: a OpenAI não faz pelo login o que os agentes precisam
  // (saída estruturada ainda sem confirmação, documentos e áudio).
  if (loginOk) return { tipo: 'parcial', texto: 'PARCIAL' };
  if (chaveOk && chatgpt) return { tipo: 'ok', texto: 'RESERVA' };
  if (chaveOk) return { tipo: 'ok', texto: 'OK_CHAVE' };

  if (chatgpt?.status === 'desconectado') {
    return { tipo: 'parada', texto: 'PARADA_DESCONECTADO' };
  }
  if (chatgpt?.status === 'limite') {
    return { tipo: 'parada', texto: 'PARADA_LIMITE' };
  }
  return { tipo: 'parada', texto: 'PARADA_SEM_CREDITO' };
};
