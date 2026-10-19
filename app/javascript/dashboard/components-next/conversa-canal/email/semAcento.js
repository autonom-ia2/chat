// Texto em minúsculas e sem acento, para busca que acha "coracao" e "coração".
export const semAcento = texto =>
  String(texto || '')
    .normalize('NFD')
    .split('')
    .filter(letra => letra.charCodeAt(0) < 0x300 || letra.charCodeAt(0) > 0x36f)
    .join('')
    .toLowerCase();
