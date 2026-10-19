// Vídeo anexado ao e-mail (#1869): o iPhone manda .mov (QuickTime), que o Chrome não
// toca. Pergunta ao próprio navegador, pelo tipo do arquivo, se ele toca; tipo que não
// conhecemos tenta tocar (e, se der erro, o cartão vira arquivo para baixar).
const TIPO_DO_VIDEO = {
  mp4: 'video/mp4',
  m4v: 'video/mp4',
  webm: 'video/webm',
  ogv: 'video/ogg',
  ogg: 'video/ogg',
  mov: 'video/quicktime',
  qt: 'video/quicktime',
  '3gp': 'video/3gpp',
  avi: 'video/x-msvideo',
  mkv: 'video/x-matroska',
  wmv: 'video/x-ms-wmv',
};

export const tocaNoNavegador = extensao => {
  const tipo = TIPO_DO_VIDEO[String(extensao || '').toLowerCase()];
  if (!tipo) return true;
  return document.createElement('video').canPlayType(tipo) !== '';
};
