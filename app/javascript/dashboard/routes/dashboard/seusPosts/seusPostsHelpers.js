// Seus posts (#2302): formatação e escolhas comuns às telas.
export const PERIODOS = [7, 30, 90];
export const PERIODO_PADRAO = 30;

export const intlLocale = locale => (locale || 'en').replace('_', '-');

// Número que a Meta não mandou (nil) é "sem número", nunca 0.
export const formatar = (valor, locale) =>
  valor === null || valor === undefined
    ? '—'
    : new Intl.NumberFormat(intlLocale(locale)).format(valor);

export const dataCurta = (valor, locale) =>
  new Date(valor).toLocaleDateString(intlLocale(locale), {
    day: 'numeric',
    month: 'short',
  });

const semValor = valor => valor === null || valor === undefined;

// "há 2 horas", "há 3 dias", no idioma da tela (F2, os comentários do post).
export const haQuanto = (valor, locale) => {
  const minutos = Math.round((Date.now() - new Date(valor).getTime()) / 60000);
  // Sem data (ou data que não se lê), sem o "há quanto": um comentário assim não derruba a lista.
  if (Number.isNaN(minutos)) return '';
  const rtf = new Intl.RelativeTimeFormat(intlLocale(locale), {
    numeric: 'auto',
  });
  if (minutos < 60) return rtf.format(-Math.max(minutos, 1), 'minute');
  if (minutos < 60 * 24) return rtf.format(-Math.round(minutos / 60), 'hour');
  return rtf.format(-Math.round(minutos / (60 * 24)), 'day');
};

// Comparação com o período anterior: texto e tom (sobe, desce, igual). Sem anterior, nada.
export const comparacao = (atual, anterior, dias, t, locale) => {
  if (semValor(atual) || semValor(anterior)) return null;
  const diferenca = atual - anterior;
  if (diferenca === 0)
    return { texto: t('SEUS_POSTS.CHANGE.SAME', { days: dias }), tom: 'igual' };
  const count = formatar(Math.abs(diferenca), locale);
  return diferenca > 0
    ? { texto: t('SEUS_POSTS.CHANGE.MORE', { count, days: dias }), tom: 'sobe' }
    : {
        texto: t('SEUS_POSTS.CHANGE.FEWER', { count, days: dias }),
        tom: 'desce',
      };
};

// A mesma comparação, curta, para dentro do quadro: o período já está escrito uma vez, acima da grade.
export const comparacaoCurta = (atual, anterior, t, locale) => {
  if (semValor(atual) || semValor(anterior)) return null;
  const diferenca = atual - anterior;
  if (diferenca === 0)
    return { texto: t('SEUS_POSTS.CHANGE.SHORT_SAME'), tom: 'igual' };
  const count = formatar(Math.abs(diferenca), locale);
  return diferenca > 0
    ? { texto: t('SEUS_POSTS.CHANGE.SHORT_MORE', { count }), tom: 'sobe' }
    : { texto: t('SEUS_POSTS.CHANGE.SHORT_FEWER', { count }), tom: 'desce' };
};

// A frase única acima da grade que explica a marca do megafone: "Pessoas que viram e Seguidores podem incluir
// anúncio. O resto é sem anúncio." Sem número marcado, "Todos os números são sem anúncio."
export const legendaDoAnuncio = (quadros, t, locale) => {
  const marcados = quadros.filter(quadro => quadro.anuncio);
  if (!marcados.length) return t('SEUS_POSTS.TILES.LEGEND_NONE');
  const nomes = new Intl.ListFormat(intlLocale(locale), {
    type: 'conjunction',
  }).format(
    // Na frase, só o primeiro nome começa com maiúscula: "Pessoas que viram, salvaram e compartilharam".
    marcados.map(({ label }, index) =>
      index
        ? label.charAt(0).toLocaleLowerCase(intlLocale(locale)) + label.slice(1)
        : label
    )
  );
  return marcados.length === quadros.length
    ? t('SEUS_POSTS.TILES.LEGEND_ALL')
    : t('SEUS_POSTS.TILES.LEGEND', { names: nomes });
};

// Um número do post contra o normal dos posts do perfil, em palavras (quem lê "1,9×" se perde): "3 vezes o
// normal", "o dobro do normal", "bem acima do normal", "acima do normal", "perto do normal" ou "abaixo do normal".
// "O dobro" e "N vezes" só quando chegam lá (com 5% de folga): 1,8× é "bem acima", não "o dobro".
const FOLGA = 0.05;
const VEZES_BEM_ACIMA = 1.5;
const VEZES_ACIMA = 1.3;
const VEZES_ABAIXO = 0.7;

export const nivelContraMedia = (valor, media) => {
  const vezes = valor / media;
  const inteiras = Math.floor(vezes + FOLGA);
  if (inteiras >= 3) return { nivel: 'TIMES', vezes: inteiras };
  if (inteiras === 2) return { nivel: 'DOUBLE', vezes: 2 };
  if (vezes >= VEZES_BEM_ACIMA) return { nivel: 'WELL_ABOVE', vezes };
  if (vezes >= VEZES_ACIMA) return { nivel: 'ABOVE', vezes };
  if (vezes <= VEZES_ABAIXO) return { nivel: 'BELOW', vezes };
  return { nivel: 'SAME', vezes };
};

// O veredito de um post contra o normal do perfil (os últimos posts sem anúncio, janela fixa do servidor). Sem
// número, impulsionado, novo e perfil sem normal não se comparam.
export const vereditoDoPost = (post, media) => {
  if (post.semInsights) return { nivel: 'NO_INSIGHTS' };
  if (post.impulsionado) return { nivel: 'BOOSTED' };
  if (post.novo || (post.recente && !post.apareceu)) return { nivel: 'NEW' };
  if (!media?.apareceu) return { nivel: 'NO_NORMAL' };
  return nivelContraMedia(post.apareceu, media.apareceu);
};

export const ICONE_DA_REDE = {
  instagram: 'i-ri-instagram-line',
  facebook: 'i-ri-facebook-circle-fill',
};
