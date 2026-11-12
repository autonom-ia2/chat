/* global axios */
import ApiClient from './ApiClient';

// #2896 — "Trazer minha lista" (relacionamentos/trazer/…). A resposta já vem
// quase no formato da tela; quem traduz o resto e dá nome às recusas é
// routes/dashboard/relacionamentos/fonte/trazerFonte.js.
//   leituras — a planilha enviada e o que o servidor achou nela. Ler demora: o
//              envio responde `lendo` e a leitura é perguntada de novo até ficar
//              `pronta` (ou `falhou`). Os problemas vêm em páginas;
//   listas   — as listas que a conta já trouxe e o andamento de cada uma.
// Tudo pede a permissão de importar contato: sem ela o servidor recusa (401 ou
// 403).
class RelacionamentosTrazerAPI extends ApiClient {
  constructor() {
    super('relacionamentos/trazer', { accountScoped: true });
  }

  enviar(arquivo) {
    const corpo = new FormData();
    corpo.append('arquivo', arquivo);
    return axios.post(`${this.url}/leituras`, corpo, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  leitura(id, pagina = 1) {
    return axios.get(`${this.url}/leituras/${id}`, { params: { pagina } });
  }

  trocarColuna(leituraId, indice, corpo) {
    return axios.patch(
      `${this.url}/leituras/${leituraId}/colunas/${indice}`,
      corpo
    );
  }

  listas() {
    return axios.get(`${this.url}/listas`);
  }

  andamento(id) {
    return axios.get(`${this.url}/listas/${id}/andamento`);
  }

  // Trazer (e continuar a lista que parou no meio) é o confirmar que a
  // importação de contatos já tinha: a leitura e a importação têm o mesmo id.
  confirmar(id) {
    return axios.post(`${this.baseUrl()}/contact_imports/${id}/confirm`);
  }
}

export default new RelacionamentosTrazerAPI();
