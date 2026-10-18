// O anexo de uma mensagem citada (#1702), como o app mostra: ícone e nome do tipo
// ("📷 Foto"), o nome do arquivo no documento e a miniatura à direita na foto e no
// vídeo. Serve à citação dentro do balão (Base.vue) e à de cima da caixa de resposta
// (CitacaoNaResposta). As chaves chegam em camelCase (balão) ou snake_case (lista).
import { escapeHtml } from 'shared/helpers/HTMLSanitizer';
import { eFigurinha } from './figurinha';
import { nomeDoArquivo } from './midia/tamanhoDoArquivo';

export const ICONES_DO_ANEXO = {
  image: 'i-ph-camera-fill',
  video: 'i-ph-video-camera-fill',
  audio: 'i-ph-microphone-fill',
  file: 'i-ph-file-fill',
  location: 'i-ph-map-pin-fill',
  contact: 'i-ph-user-fill',
  midia: 'i-ph-paperclip',
  figurinha: 'i-ph-sticker-fill',
};

// Chaves escritas por extenso: a trava de i18n confere cada uma.
export const NOMES_DO_ANEXO = {
  image: 'CONVERSA_CANAL.CITACAO.FOTO',
  video: 'CONVERSA_CANAL.CITACAO.VIDEO',
  audio: 'CONVERSA_CANAL.CITACAO.AUDIO',
  file: 'CONVERSA_CANAL.CITACAO.DOCUMENTO',
  location: 'CONVERSA_CANAL.CITACAO.LOCALIZACAO',
  contact: 'CONVERSA_CANAL.CITACAO.CONTATO',
  midia: 'CONVERSA_CANAL.CITACAO.MIDIA',
  figurinha: 'CONVERSA_CANAL.MIDIA.FIGURINHA',
};

const primeiroAnexo = mensagem => mensagem?.attachments?.[0] || null;

// O tipo como a citação o chama; null quando não há anexo que ela conheça.
export const tipoDoAnexoCitado = mensagem => {
  const anexo = primeiroAnexo(mensagem);
  if (!anexo) return null;
  if (eFigurinha(anexo)) return 'figurinha';
  const tipo = anexo.fileType ?? anexo.file_type;
  return NOMES_DO_ANEXO[tipo] ? tipo : null;
};

export const iconeDoAnexoCitado = mensagem =>
  ICONES_DO_ANEXO[tipoDoAnexoCitado(mensagem)] || '';

// Texto da citação quando a mensagem citada não tem texto: o nome do tipo, ou o
// nome do arquivo no documento (como o app escreve "📄 contrato.pdf").
export const previaDoAnexoCitado = (mensagem, t) => {
  const tipo = tipoDoAnexoCitado(mensagem);
  if (!tipo) return t('CONVERSA_CANAL.CITACAO.SEM_TEXTO');
  if (tipo === 'file') {
    const anexo = primeiroAnexo(mensagem);
    const nome = nomeDoArquivo({ dataUrl: anexo.dataUrl ?? anexo.data_url });
    // A prévia é HTML (v-dompurify-html): o nome vem do cliente e sai escapado, para
    // "<b>contrato</b>.pdf" aparecer como foi escrito.
    if (nome) return escapeHtml(nome);
  }
  return t(NOMES_DO_ANEXO[tipo]);
};

// Miniatura à direita: a foto (ou a figurinha) por inteiro, se não houver miniatura;
// o vídeo só com a miniatura (o arquivo do vídeo não vira imagem).
export const miniaturaDoAnexoCitado = mensagem => {
  const anexo = primeiroAnexo(mensagem);
  const tipo = anexo?.fileType ?? anexo?.file_type;
  const miniatura = anexo?.thumbUrl ?? anexo?.thumb_url;
  if (tipo === 'image') {
    return miniatura || anexo.dataUrl || anexo.data_url || '';
  }
  if (tipo === 'video') return miniatura || '';
  return '';
};
