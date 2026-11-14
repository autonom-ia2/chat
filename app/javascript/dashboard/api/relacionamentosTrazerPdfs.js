/* global axios */
import ApiClient from './ApiClient';

// #2899 (E6.3) — "Trazer por PDFs" (relacionamentos/trazer/seguros/leituras…):
// enviar os PDFs, o Conferir do lote, mudar um PDF dele, trazer, o andamento,
// os lotes já enviados e o desfazer com a prévia. Só existe na conta com a
// carteira de seguros; enviar pede a leitura de PDF liberada (422
// `leitura_desligada`). Quem dá nome às recusas é fonte/trazerPdfsFonte.js.
class RelacionamentosTrazerPdfsAPI extends ApiClient {
  constructor() {
    super('relacionamentos/trazer/seguros/leituras', { accountScoped: true });
  }

  enviar(arquivos) {
    const corpo = new FormData();
    arquivos.forEach(arquivo => corpo.append('arquivos[]', arquivo));
    return axios.post(this.url, corpo, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  lote(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // `pedido`: { campos: { tipo, seguradora, termina, nome }, confirmar: [],
  // recusar: [], fora }. Responde o Conferir inteiro.
  mudarItem(id, itemId, pedido) {
    return axios.patch(`${this.url}/${id}/itens/${itemId}`, pedido);
  }

  trazer(id) {
    return axios.post(`${this.url}/${id}/trazer`);
  }

  andamento(id) {
    return axios.get(`${this.url}/${id}/andamento`);
  }

  historico() {
    return axios.get(this.url);
  }

  previaDoDesfazer(id) {
    return axios.get(`${this.url}/${id}/previa_do_desfazer`);
  }

  desfazer(id) {
    return axios.post(`${this.url}/${id}/desfazer`);
  }
}

export default new RelacionamentosTrazerPdfsAPI();
