import { ApiError, getPage } from '../api';

// O `form_token` que o GET da página entrega vale de 2 s a 2 h no servidor. Quem deixa a página aberta e volta depois
// não pode cair em "Não deu para marcar" sem fim: perto de vencer (1h45) buscamos a página de novo antes de enviar; e
// se o servidor recusar com `booking_failed` um token já velho, renovamos e reenviamos UMA vez, com a mesma chave do
// pedido. Token novo só vale depois de 2 s, então esperamos esse tempo antes do envio.
export const FORM_TOKEN_REFRESH_MS = 105 * 60 * 1000;
export const FORM_TOKEN_STALE_MS = 60 * 60 * 1000;
export const FORM_TOKEN_MIN_AGE_MS = 2100;

const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export function useFormToken({ page, slug, preview }) {
  let issuedAt = Date.now();

  const age = () => Date.now() - issuedAt;
  const markIssued = () => {
    issuedAt = Date.now();
  };

  const refresh = async () => {
    const data = await getPage(slug.value, preview);
    if (!data?.form_token) throw new ApiError(422, 'booking_failed');
    page.value = { ...page.value, form_token: data.form_token };
    markIssued();
    await wait(FORM_TOKEN_MIN_AGE_MS);
  };

  // `send` monta o pedido na hora (lê o token atual) e envia.
  const sendWithFreshToken = async send => {
    if (age() >= FORM_TOKEN_REFRESH_MS) await refresh();
    try {
      return await send();
    } catch (error) {
      if (error?.code !== 'booking_failed' || age() < FORM_TOKEN_STALE_MS) {
        throw error;
      }
      await refresh();
      return send();
    }
  };

  return { markIssued, sendWithFreshToken };
}
