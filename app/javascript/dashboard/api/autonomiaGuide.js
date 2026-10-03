/* global axios */
import ApiClient from './ApiClient';

const EXTENSOES_DE_AUDIO = {
  'audio/ogg': 'ogg',
  'audio/mp3': 'mp3',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/mp4': 'mp4',
  'video/mp4': 'mp4',
  'audio/webm': 'webm',
  'video/webm': 'webm',
};

// Guia da Plataforma — onboarding/suporte global (gated server-side by the account's Autonomia
// eligibility = ENV master + the Kanban AI key). O que tem desfazer o Guia faz no próprio turno
// (#855); `executarAcao` é só para o que não tem volta, depois da confirmação explícita na tela.
class AutonomiaGuideAPI extends ApiClient {
  constructor() {
    super('autonomia/guide', { accountScoped: true });
  }

  // history: [{ role: 'user' | 'assistant', content }]
  // routeContext: the current route name (so the guide knows where the user is).
  //
  // #572 — não devolve a resposta: abre o pedido e devolve { id, status }. O
  // Guia trabalha num job, e a resposta se busca em `resposta(id)`. Responder
  // aqui dentro esbarrava no teto de 15s do servidor e morria com erro 500.
  chat({ message, history, routeContext, arquivos = [] } = {}) {
    return axios.post(`${this.url}/chat`, {
      message,
      history,
      route_context: routeContext,
      arquivos,
    });
  }

  // #857 — o que a pessoa falou ao microfone, em texto: { texto }.
  // #895 — o transcritor decide o formato pela extensão do nome, então ela tem
  // que bater com o áudio de verdade: OGG no Chrome e no Firefox, MP3 no Safari.
  transcrever(audio) {
    const form = new FormData();
    const tipo = (audio.type || '').split(';')[0].trim();
    const extensao = EXTENSOES_DE_AUDIO[tipo] || 'webm';
    form.append('file', audio, `voz.${extensao}`);
    return axios.post(`${this.url}/transcricao`, form);
  }

  // #857 — anexa um arquivo à conversa; volta { signed_id, nome }.
  enviarArquivo(file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/arquivos`, form);
  }

  // { status: 'pending' } enquanto o Guia pensa; depois 'done' com a resposta
  // (text, navigation, acao, retido…) ou 'failed'.
  resposta(id) {
    return axios.get(`${this.url}/chat/${id}`);
  }

  // Só é chamado depois da confirmação explícita na tela. O backend recusa o que
  // estiver fora do catálogo de ações e o que a pessoa não puder fazer.
  executarAcao({ acao, dados } = {}) {
    return axios.post(`${this.url}/acoes/executar`, { acao, dados });
  }

  // #855 — o que o Guia fez para esta pessoa nos últimos 5 dias.
  execucoes() {
    return axios.get(`${this.url}/execucoes`);
  }

  // #855 — volta a conta ao estado de antes daquele turno do Guia.
  desfazer(id) {
    return axios.post(`${this.url}/execucoes/${id}/desfazer`);
  }
}

export default new AutonomiaGuideAPI();
