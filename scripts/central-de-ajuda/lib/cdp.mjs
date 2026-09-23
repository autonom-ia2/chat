/* eslint-disable no-await-in-loop -- espera sequencial de propósito: cada
   tentativa de conectar no Chrome depende do resultado da anterior. */
// Cliente CDP mínimo, sem dependência nova: usa o WebSocket global do Node 24
// e fetch (também global) para falar com o Chrome via
// --remote-debugging-port. Sem puppeteer, sem playwright.

import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME_BIN =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

export async function portaLivre() {
  return new Promise((resolve, reject) => {
    const servidor = createServer();
    servidor.unref();
    servidor.on('error', reject);
    servidor.listen(0, '127.0.0.1', () => {
      const { port } = servidor.address();
      servidor.close(() => resolve(port));
    });
  });
}

async function aguardarChromeVivo(porta, tentativas = 100) {
  const url = `http://127.0.0.1:${porta}/json/version`;
  for (let i = 0; i < tentativas; i += 1) {
    try {
      const resposta = await fetch(url);
      if (resposta.ok) return;
    } catch {
      // Chrome ainda subindo; tenta de novo.
    }
    await new Promise(resolve => {
      setTimeout(resolve, 100);
    });
  }
  throw new Error(`Chrome não respondeu em ${url} a tempo`);
}

/**
 * Sobe um Chrome headless dedicado a esta gravação, com perfil e porta
 * próprios (nunca reaproveita um Chrome do usuário).
 */
export async function abrirChromeHeadless() {
  const porta = await portaLivre();
  const perfil = mkdtempSync(join(tmpdir(), 'central-de-ajuda-chrome-'));

  const processo = spawn(
    CHROME_BIN,
    [
      '--headless=new',
      `--remote-debugging-port=${porta}`,
      `--user-data-dir=${perfil}`,
      '--window-size=1280,800',
      '--hide-scrollbars',
      '--disable-gpu',
      '--no-first-run',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--disable-background-timer-throttling',
      '--disable-backgrounding-occluded-windows',
      '--disable-renderer-backgrounding',
      'about:blank',
    ],
    { stdio: 'ignore' }
  );

  await aguardarChromeVivo(porta);

  return {
    porta,
    perfil,
    encerrar() {
      processo.kill('SIGKILL');
      try {
        rmSync(perfil, { recursive: true, force: true });
      } catch {
        // perfil temporário; falha ao limpar não é fatal.
      }
    },
  };
}

async function acharAlvoDePagina(porta) {
  const alvos = await fetch(`http://127.0.0.1:${porta}/json`).then(r =>
    r.json()
  );
  const pagina = alvos.find(alvo => alvo.type === 'page');
  if (!pagina) throw new Error('Nenhum alvo "page" encontrado no Chrome');
  return pagina;
}

/**
 * Cliente CDP mínimo sobre um único WebSocket (a webSocketDebuggerUrl de uma
 * aba), sem sessões Target.* — como a conexão é direta com a página, os
 * comandos e eventos não levam sessionId.
 */
class ClienteCDP {
  constructor(wsUrl) {
    this.ws = new WebSocket(wsUrl);
    this.proximoId = 1;
    this.pendentes = new Map();
    this.ouvintes = new Map();
    this.pronto = new Promise((resolve, reject) => {
      this.ws.addEventListener('open', () => resolve());
      this.ws.addEventListener('error', reject);
    });
    this.ws.addEventListener('message', evento => {
      const mensagem = JSON.parse(evento.data);
      if (mensagem.id !== undefined) {
        const pendente = this.pendentes.get(mensagem.id);
        if (!pendente) return;
        this.pendentes.delete(mensagem.id);
        if (mensagem.error) {
          pendente.reject(
            new Error(`CDP ${mensagem.error.message} (${mensagem.error.code})`)
          );
        } else {
          pendente.resolve(mensagem.result);
        }
        return;
      }
      const lista = this.ouvintes.get(mensagem.method);
      if (lista) lista.forEach(fn => fn(mensagem.params));
    });
  }

  async enviar(method, params = {}) {
    await this.pronto;
    const id = this.proximoId;
    this.proximoId += 1;
    return new Promise((resolve, reject) => {
      this.pendentes.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  em(method, fn) {
    if (!this.ouvintes.has(method)) this.ouvintes.set(method, []);
    this.ouvintes.get(method).push(fn);
  }

  fechar() {
    this.ws.close();
  }
}

export async function conectarPagina(porta) {
  const alvo = await acharAlvoDePagina(porta);
  const cliente = new ClienteCDP(alvo.webSocketDebuggerUrl);
  await cliente.pronto;
  return cliente;
}
