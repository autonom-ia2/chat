import Cookies from 'js-cookie';

// devise-token-auth pede access-token / client / uid em toda chamada. O
// navigator.sendBeacon não manda cabeçalho, então quem chama com
// fetch+keepalive ao sair da página (encerrar a ligação do WhatsApp, o "Feito"
// pendente da Lista do CRM, #2283) monta os cabeçalhos a partir do cookie
// cw_d_session_info que o painel grava no login. null sem sessão.
export const getDeviseAuthHeaders = () => {
  try {
    const raw = Cookies.get('cw_d_session_info');
    if (!raw) return null;
    const session = JSON.parse(raw);
    return {
      'access-token': session['access-token'] || '',
      client: session.client || '',
      uid: session.uid || '',
      expiry: session.expiry || '',
      'token-type': session['token-type'] || 'Bearer',
    };
  } catch (_) {
    return null;
  }
};
