import { LOGO_DARK_MODES, logoDarkModeOf } from './publicPage';

// A logo no tema escuro (#1295), para o cartão da Logo no passo "Sua marca".
// O servidor diz de onde ela veio (`brand.logo_dark_source`); aqui isso vira a
// chave da frase que explica (BOOKING.LOOK.LOGO_DARK.ORIGIN.*) e o jeito de
// mostrar, que é o mesmo da página pública (`logoDarkModeOf`).
const UPLOADED = 'uploaded';

// 'NONE' | 'UPLOADED' | 'GENERATED' | 'SAME' | 'PLATE'
export const logoDarkOrigin = page => {
  if (!page.logo_url) return 'NONE';
  const source = page.brand?.logo_dark_source;
  if (page.logo_dark_url) return source === UPLOADED ? 'UPLOADED' : 'GENERATED';
  return source === 'same' ? 'SAME' : 'PLATE';
};

// O que o quadro "Em fundo escuro" mostra: a imagem e se ela vai na placa.
export const logoDarkLook = page => {
  const mode = logoDarkModeOf({
    darkUrl: page.logo_dark_url,
    source: page.brand?.logo_dark_source,
  });
  return {
    url: page.logo_dark_url || page.logo_url || '',
    onPlate: mode === LOGO_DARK_MODES.PLATE,
  };
};
