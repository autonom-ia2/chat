// #2899 (E6.4) — de onde "Trazer por PDFs" lê e para onde escreve: o servidor
// (api/relacionamentosTrazerPdfs.js), com as recusas nomeadas como no resto da
// carteira (fonte/carteiraFonteReal.js: 422 é `RECUSADO`, com o código). A
// demonstração não tem leitura de PDF, então esta tela não tem demonstração:
// a porta (pages/TrazerPage.vue) nem a mostra sem a leitura liberada.
import PdfsAPI from 'dashboard/api/relacionamentosTrazerPdfs';
import { noServidor } from './carteiraFonteReal';

export const trazerPdfsFonte = () => ({
  enviar: arquivos => noServidor(() => PdfsAPI.enviar(arquivos)),
  lote: id => noServidor(() => PdfsAPI.lote(id)),
  mudarItem: (id, itemId, pedido) =>
    noServidor(() => PdfsAPI.mudarItem(id, itemId, pedido)),
  trazer: id => noServidor(() => PdfsAPI.trazer(id)),
  andamento: id => noServidor(() => PdfsAPI.andamento(id)),
  historico: () => noServidor(() => PdfsAPI.historico()),
  previaDoDesfazer: id => noServidor(() => PdfsAPI.previaDoDesfazer(id)),
  desfazer: id => noServidor(() => PdfsAPI.desfazer(id)),
});
