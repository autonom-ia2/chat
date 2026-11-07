// #2472 F0: adaptador falso do protótipo. Cada `?demo=` é um estado da tela.
// Na F1 este arquivo dá lugar ao endpoint da conta; a tela não muda.
const CONTA = 'dono@empresa.com.br';

const ESTADOS = {
  vazio: { chatgpt: null, chave: null },
  so_chave: { chatgpt: null, chave: { status: 'funcionando', fim: '8f2Q' } },
  so_login: { chatgpt: { status: 'funcionando', email: CONTA }, chave: null },
  os_dois: {
    chatgpt: { status: 'funcionando', email: CONTA },
    chave: { status: 'funcionando', fim: '8f2Q' },
  },
  reserva: {
    chatgpt: { status: 'limite', email: CONTA },
    chave: { status: 'funcionando', fim: '8f2Q' },
  },
  sem_credito: { chatgpt: null, chave: { status: 'sem_credito', fim: '8f2Q' } },
  limite: { chatgpt: { status: 'limite', email: CONTA }, chave: null },
  desconectado: {
    chatgpt: { status: 'desconectado', email: CONTA },
    chave: null,
  },
};

export const estadosDeExemplo = Object.keys(ESTADOS);

export const fontesDeExemplo = demo => ({
  loginDisponivel: demo !== 'em_breve',
  ...(ESTADOS[demo] || ESTADOS.vazio),
});
