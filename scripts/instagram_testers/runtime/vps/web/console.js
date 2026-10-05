import RFB from './novnc/core/rfb.js';

const language = navigator.language.startsWith('pt') ? 'pt-BR' : 'en';
const copy = {
  'pt-BR': {
    title: 'Navegador privado do Instagram',
    instructions:
      'Ao terminar, feche o Chrome remoto para finalizar. Fechar esta aba não finaliza o pedido.',
    waiting: 'Aguardando o navegador…',
    ready: 'Navegador disponível. Conecte para continuar.',
    connect: 'Conectar ao navegador',
    connecting: 'Conectando ao navegador…',
    connected: 'Ao terminar, feche o Chrome remoto para finalizar.',
    disconnected: 'Conexão encerrada. Aguardando o navegador…',
    finished: 'Acesso encerrado. Volte ao painel para continuar.',
  },
  en: {
    title: 'Private Instagram browser',
    instructions:
      'When finished, close the remote Chrome to complete the request. Closing this tab does not complete it.',
    waiting: 'Waiting for the browser…',
    ready: 'Browser available. Connect to continue.',
    connect: 'Connect to browser',
    connecting: 'Connecting to browser…',
    connected:
      'When finished, close the remote Chrome to complete the request.',
    disconnected: 'Connection closed. Waiting for the browser…',
    finished: 'Access ended. Return to the dashboard to continue.',
  },
}[language];
const status = document.getElementById('status');
const connect = document.getElementById('connect');
const screen = document.getElementById('screen');
const base = new URL('../', import.meta.url);
let rfb;
let finished = false;
document.documentElement.lang = language;
document.title = copy.title;
document.getElementById('title').textContent = copy.title;
document.getElementById('instructions').textContent = copy.instructions;
connect.textContent = copy.connect;

connect.addEventListener('click', () => {
  connect.disabled = true;
  const url = new URL('ws', base);
  url.protocol = 'wss:';
  rfb = new RFB(screen, url.href);
  rfb.scaleViewport = false;
  rfb.resizeSession = false;
  status.textContent = copy.connecting;
  rfb.addEventListener('connect', () => {
    status.textContent = copy.connected;
  });
  rfb.addEventListener('disconnect', () => {
    rfb = undefined;
    if (!finished) {
      status.textContent = copy.disconnected;
      connect.disabled = false;
    }
  });
});

async function refresh() {
  try {
    const response = await fetch(new URL('status', base), {
      credentials: 'same-origin',
      cache: 'no-store',
    });
    if (!response.ok) throw new Error('denied');
    const { state } = await response.json();
    if (!rfb) {
      connect.disabled = state !== 'ready';
      status.textContent = state === 'ready' ? copy.ready : copy.waiting;
    }
  } catch {
    finished = true;
    connect.disabled = true;
    rfb?.disconnect();
    screen.replaceChildren();
    status.textContent = copy.finished;
  }
  if (!finished) window.setTimeout(refresh, 1000);
}

window.addEventListener('pagehide', () => {
  finished = true;
  rfb?.disconnect();
});
refresh();
