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
  // routeParams: os parâmetros da rota (#859) — o servidor guarda só os números, como
  // "Registro aberto na tela: id=42". É contexto, não autorização.
  //
  // #572 — não devolve a resposta: abre o pedido e devolve { id, status }. O
  // Guia trabalha num job, e a resposta se busca em `resposta(id)`. Responder
  // aqui dentro esbarrava no teto de 15s do servidor e morria com erro 500.
  //
  // #934 — `tela`: o que a pessoa tem aberto, selecionado e filtrado (`contextoAtual`).
  // Sem ele (o × da etiqueta), a pergunta vai só com a rota, como antes.
  //
  // #861 — `conversaId` continua a conversa guardada; sem ele, o servidor abre
  // outra e devolve o id em `conversa_id`. `anexos` ({ nome, tipo }) é o que o
  // balão mostrou, para a conversa reabrir igual. `history` fica só durante o
  // deploy: o servidor monta o histórico a partir da conversa guardada.
  chat({
    message,
    history,
    routeContext,
    routeParams,
    tela,
    arquivos = [],
    conversaId = null,
    anexos = [],
  } = {}) {
    return axios.post(`${this.url}/chat`, {
      message,
      history,
      route_context: routeContext,
      route_params: routeParams,
      tela,
      arquivos,
      conversa_id: conversaId,
      anexos,
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
  // #861 — `pedidoId` guarda o desfecho na conversa: reabrir não mostra os
  // botões de novo.
  executarAcao({ acao, dados, pedidoId = null } = {}) {
    return axios.post(`${this.url}/acoes/executar`, {
      acao,
      dados,
      pedido_id: pedidoId,
    });
  }

  // #861 — a conversa mais recente, para reabrir ao abrir o painel; `{}` se
  // não houver nenhuma.
  conversaAtual() {
    return axios.get(`${this.url}/conversas/atual`);
  }

  // #861 — as conversas anteriores, 20 por página: { conversas }.
  conversas(page = 1) {
    return axios.get(`${this.url}/conversas`, { params: { page } });
  }

  conversa(id) {
    return axios.get(`${this.url}/conversas/${id}`);
  }

  // Sem desfazer: a tela pede confirmação antes.
  apagarConversa(id) {
    return axios.delete(`${this.url}/conversas/${id}`);
  }

  // #855 — o que o Guia fez para esta pessoa nos últimos 5 dias.
  execucoes() {
    return axios.get(`${this.url}/execucoes`);
  }

  // #855 — volta a conta ao estado de antes daquele turno do Guia.
  desfazer(id) {
    return axios.post(`${this.url}/execucoes/${id}/desfazer`);
  }

  // #933 — o que o Guia lembra: { pessoais, corretora, pode_editar_corretora, limites }.
  memorias() {
    return axios.get(`${this.url}_memorias`);
  }

  corrigirMemoria(id, texto) {
    return axios.patch(`${this.url}_memorias/${id}`, { texto });
  }

  // Sem desfazer.
  apagarMemoria(id) {
    return axios.delete(`${this.url}_memorias/${id}`);
  }

  // #935 — os avisos do Guia para quem pede: { avisos, novos }. Só administrador.
  avisos(estado) {
    return axios.get(`${this.baseUrl()}/autonomia/avisos`, {
      params: { estado },
    });
  }

  // #935 — 'visto' quando a pessoa abre o Guia.
  marcarAviso(id, estado) {
    return axios.patch(`${this.baseUrl()}/autonomia/avisos/${id}`, { estado });
  }
}

export default new AutonomiaGuideAPI();
