/* global axios */
import ApiClient from './ApiClient';

// #2896 — "Trazer minha lista" (relacionamentos/trazer/…). A resposta já vem
// quase no formato da tela; quem traduz o resto e dá nome às recusas é
// routes/dashboard/relacionamentos/fonte/trazerFonte.js.
//   leituras — a planilha enviada e o que o servidor achou nela. Ler demora: o
//              envio responde `lendo` e a leitura é perguntada de novo até ficar
//              `pronta` (ou `falhou`). Os problemas vêm em páginas. É na leitura
//              que a pessoa confere: responde às perguntas, conserta ou deixa de
//              fora cada linha, troca o destino de uma coluna e, no fim, traz;
//   listas   — as listas que a conta já trouxe, o andamento de cada uma e o
//              desfazer de uma lista gravada, com a prévia do que ele faria.
// Tudo pede a permissão de importar contato: sem ela o servidor responde 401.
// Depois de trazida, a leitura responde 404 e as rotas de linha, 422.
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

  responder(leituraId, corpo) {
    return axios.patch(`${this.url}/leituras/${leituraId}/respostas`, corpo);
  }

  // `corpo` é `{ valor }` (o telefone, o e-mail ou o nome certo) ou
  // `{ ficar_com }` (o número de qual das duas linhas repetidas fica).
  consertar(leituraId, linha, corpo) {
    return axios.patch(
      `${this.url}/leituras/${leituraId}/linhas/${linha}`,
      corpo
    );
  }

  deixarDeFora(leituraId, linha) {
    return axios.post(
      `${this.url}/leituras/${leituraId}/linhas/${linha}/deixar_de_fora`
    );
  }

  reabrir(leituraId, linha) {
    return axios.post(
      `${this.url}/leituras/${leituraId}/linhas/${linha}/reabrir`
    );
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

  // Quantas pessoas saem, quantas ficam e quantas voltam a ser como eram.
  previaDoDesfazer(id) {
    return axios.get(`${this.url}/listas/${id}/previa_do_desfazer`);
  }

  // Só marca a lista como `desfazendo` e responde na hora (202): quem desfaz é
  // o servidor, depois. A lista que ainda não foi gravada é recusada (422).
  desfazer(id) {
    return axios.post(`${this.url}/listas/${id}/desfazer`);
  }

  // Fecha a conferência e começa a trazer: o que ficou aberto ou de fora não
  // entra.
  trazer(leituraId) {
    return axios.post(`${this.url}/leituras/${leituraId}/trazer`);
  }

  // Continuar a lista que parou no meio é o confirmar que a importação de
  // contatos já tinha: a leitura e a importação têm o mesmo id.
  confirmar(id) {
    return axios.post(`${this.baseUrl()}/contact_imports/${id}/confirm`);
  }
}

export default new RelacionamentosTrazerAPI();
