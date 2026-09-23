/* eslint-disable no-await-in-loop -- cada passo do mouse/teclado depende do
   anterior já ter sido despachado; é sequencial de propósito. */
// Ajuda a mexer na página gravada: injeta o cursor visível e o estilo de
// destaque, acha o elemento-alvo de cada cena (por texto exato ou seletor
// CSS — sem regex) e movimenta o mouse/teclado via CDP.

const COR_DESTAQUE = '#2781F6';

// Roda uma única vez por documento carregado (a SPA não recarrega entre
// cliques dentro da conta, só quando o motor navega de propósito).
const SCRIPT_INJETADO = `
(function () {
  if (window.__gravacao) return;

  var cursor = document.createElement('div');
  cursor.id = '__gravacao-cursor';
  cursor.style.cssText = [
    'position:fixed', 'top:0', 'left:0', 'width:0', 'height:0',
    'pointer-events:none', 'z-index:2147483647',
    'transform:translate(-3px,-2px)',
  ].join(';');
  cursor.innerHTML =
    '<svg width="30" height="30" viewBox="0 0 30 30" xmlns="http://www.w3.org/2000/svg" ' +
    'style="filter:drop-shadow(0 1px 3px rgba(0,0,0,.55))">' +
    '<path d="M5 3 L5 25 L11 20 L15 27 L19.5 24.7 L15.5 18 L23 18 Z" ' +
    'fill="#ffffff" stroke="#1b1b1b" stroke-width="1.6" stroke-linejoin="round"/>' +
    '</svg>';
  document.documentElement.appendChild(cursor);

  window.addEventListener(
    'mousemove',
    function (evento) {
      cursor.style.left = evento.clientX + 'px';
      cursor.style.top = evento.clientY + 'px';
    },
    { capture: true }
  );

  var estilo = document.createElement('style');
  estilo.textContent =
    '.__gravacao-destaque{' +
    'border-radius:10px!important;' +
    'box-shadow:0 0 0 3px ${COR_DESTAQUE},0 0 0 7px rgba(255,255,255,.92)!important;' +
    'transition:none!important;' +
    '}' +
    /* rack-mini-profiler é debug de dev, nunca aparece em produção — não
       entra na gravação. */
    '#mini-profiler, .profiler-results{display:none!important;}';
  document.head.appendChild(estilo);

  function elementoVisivel(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  // Acha o elemento mais específico (mais interno) cujo texto bate: quando
  // um <div> só embrulha um <button> com o mesmo texto, os dois têm o mesmo
  // textContent — sem isso, o <div> (ancestral, vem antes na ordem do
  // documento) ganharia do <button>, que é o alvo de verdade do clique.
  function encontrarPorTexto(texto) {
    var candidatos = Array.prototype.filter.call(
      document.querySelectorAll('body *'),
      function (n) {
        return n.textContent && n.textContent.trim() === texto;
      }
    );
    var maisEspecificos = candidatos.filter(function (c) {
      return !candidatos.some(function (outro) {
        return outro !== c && c.contains(outro);
      });
    });
    maisEspecificos.sort(function (a, b) {
      return a.textContent.length - b.textContent.length;
    });
    return maisEspecificos[0] || null;
  }

  function encontrarElemento(spec) {
    if (spec.seletor) return document.querySelector(spec.seletor);
    if (spec.texto) return encontrarPorTexto(spec.texto);
    return null;
  }

  function achar(spec) {
    var el = encontrarElemento(spec);
    if (!elementoVisivel(el)) return null;
    var r = el.getBoundingClientRect();
    return {
      x: r.left,
      y: r.top,
      width: r.width,
      height: r.height,
      centroX: r.left + r.width / 2,
      centroY: r.top + r.height / 2,
    };
  }

  window.__gravacao = {
    achar: achar,
    limparDestaque: function () {
      document.querySelectorAll('.__gravacao-destaque').forEach(function (el) {
        el.classList.remove('__gravacao-destaque');
      });
    },
    destacar: function (spec) {
      window.__gravacao.limparDestaque();
      var el = encontrarElemento(spec);
      if (el) el.classList.add('__gravacao-destaque');
      return !!el;
    },
    rolarAte: function (spec) {
      var el = encontrarElemento(spec);
      if (!el) return false;
      el.scrollIntoView({
        behavior: 'instant',
        block: spec.blocoRolagem || 'center',
      });
      return true;
    },
  };
})();
`;

export async function injetar(cliente) {
  await cliente.enviar('Runtime.evaluate', {
    expression: SCRIPT_INJETADO,
    awaitPromise: false,
  });
}

async function achar(
  cliente,
  alvo,
  { tentativas = 40, intervaloMs = 100 } = {}
) {
  for (let i = 0; i < tentativas; i += 1) {
    const { result } = await cliente.enviar('Runtime.evaluate', {
      expression: `window.__gravacao.achar(${JSON.stringify(alvo)})`,
      returnByValue: true,
    });
    if (result.value) return result.value;
    await new Promise(resolve => {
      setTimeout(resolve, intervaloMs);
    });
  }
  throw new Error(
    `Alvo não encontrado (ou invisível) depois de ${tentativas * intervaloMs}ms: ${JSON.stringify(alvo)}`
  );
}

export async function limparDestaque(cliente) {
  await cliente.enviar('Runtime.evaluate', {
    expression: 'window.__gravacao.limparDestaque()',
  });
}

// Sempre rola o alvo pra dentro da tela antes de medir o retângulo final —
// getBoundingClientRect não garante que o elemento esteja realmente visível
// (pode estar abaixo da dobra), e clicar fora do viewport não acerta nada.
export async function destacarEAcharRetangulo(cliente, alvo, opcoesAchar) {
  await achar(cliente, alvo, opcoesAchar);
  await cliente.enviar('Runtime.evaluate', {
    expression: `window.__gravacao.rolarAte(${JSON.stringify(alvo)})`,
  });
  await new Promise(resolve => {
    setTimeout(resolve, 150);
  });
  const retangulo = await achar(cliente, alvo, opcoesAchar);
  await cliente.enviar('Runtime.evaluate', {
    expression: `window.__gravacao.destacar(${JSON.stringify(alvo)})`,
  });
  return retangulo;
}


// --- mouse ---

async function dispatchMouse(cliente, type, x, y, button = 'none') {
  await cliente.enviar('Input.dispatchMouseEvent', {
    type,
    x,
    y,
    button,
    buttons: type === 'mousePressed' ? 1 : 0,
    clickCount: type === 'mousePressed' || type === 'mouseReleased' ? 1 : 0,
  });
}

let posicaoAtual = { x: 10, y: 10 };

export async function moverCursor(
  cliente,
  destinoX,
  destinoY,
  duracaoMs = 550
) {
  const origem = posicaoAtual;
  const passos = Math.max(6, Math.round(duracaoMs / 25));
  for (let i = 1; i <= passos; i += 1) {
    const t = i / passos;
    const x = origem.x + (destinoX - origem.x) * t;
    const y = origem.y + (destinoY - origem.y) * t;
    await dispatchMouse(cliente, 'mouseMoved', x, y);
    await new Promise(resolve => {
      setTimeout(resolve, duracaoMs / passos);
    });
  }
  posicaoAtual = { x: destinoX, y: destinoY };
}

export async function clicar(cliente, x, y) {
  await dispatchMouse(cliente, 'mousePressed', x, y, 'left');
  await new Promise(resolve => {
    setTimeout(resolve, 60);
  });
  await dispatchMouse(cliente, 'mouseReleased', x, y, 'left');
}

// --- teclado ---

async function pressionarEnter(cliente) {
  await cliente.enviar('Input.dispatchKeyEvent', {
    type: 'rawKeyDown',
    windowsVirtualKeyCode: 13,
    key: 'Enter',
    code: 'Enter',
  });
  await cliente.enviar('Input.dispatchKeyEvent', {
    type: 'keyUp',
    windowsVirtualKeyCode: 13,
    key: 'Enter',
    code: 'Enter',
  });
}

export async function digitarLinhas(cliente, linhas, msPorPalavra = 170) {
  for (let i = 0; i < linhas.length; i += 1) {
    const palavras = linhas[i].split(' ');
    for (let p = 0; p < palavras.length; p += 1) {
      const texto = (p === 0 ? '' : ' ') + palavras[p];
      await cliente.enviar('Input.insertText', { text: texto });
      await new Promise(resolve => {
        setTimeout(resolve, msPorPalavra);
      });
    }
    if (i < linhas.length - 1) {
      await pressionarEnter(cliente);
      await new Promise(resolve => {
        setTimeout(resolve, 150);
      });
    }
  }
}

// --- checagens ---

const TERMOS_PROIBIDOS = ['Autonom', 'Hub2You', 'Chatwoot', 'Chat2You'];

// Varre os nós de texto visíveis da página e falha se algum termo proibido
// aparecer dentro do retângulo (em px CSS) que o ffmpeg vai recortar — não
// é "olhar o quadro depois", é medir o texto real contra o recorte real.
export async function verificarSemMarca(cliente, recorteCss, legendaCena) {
  const { result } = await cliente.enviar('Runtime.evaluate', {
    expression: `
      (function () {
        var termos = ${JSON.stringify(TERMOS_PROIBIDOS)};
        var crop = ${JSON.stringify(recorteCss)};
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var achados = [];
        var no;
        while ((no = walker.nextNode())) {
          var texto = no.textContent;
          if (!texto) continue;
          var termo = null;
          for (var t = 0; t < termos.length; t += 1) {
            if (texto.indexOf(termos[t]) !== -1) {
              termo = termos[t];
              break;
            }
          }
          if (!termo) continue;
          var range = document.createRange();
          range.selectNodeContents(no);
          var rects = range.getClientRects();
          for (var i = 0; i < rects.length; i += 1) {
            var r = rects[i];
            if (r.width === 0 || r.height === 0) continue;
            var intersecta =
              r.left < crop.x + crop.w &&
              r.right > crop.x &&
              r.top < crop.y + crop.h &&
              r.bottom > crop.y;
            if (intersecta) {
              achados.push(termo + ': "' + texto.trim().slice(0, 80) + '"');
              break;
            }
          }
        }
        return achados;
      })()
    `,
    returnByValue: true,
  });
  const achados = result.value || [];
  if (achados.length) {
    throw new Error(
      `Marca visível no recorte da cena "${legendaCena}": ${achados.join(' | ')}`
    );
  }
}

// Espera um texto aparecer em qualquer lugar visível da página — usado para
// não cortar uma cena de navegação enquanto a tela de destino ainda está
// com "Carregando...".
export async function esperarTexto(
  cliente,
  texto,
  { tentativas = 60, intervaloMs = 200 } = {}
) {
  for (let i = 0; i < tentativas; i += 1) {
    const { result } = await cliente.enviar('Runtime.evaluate', {
      expression: `document.body.innerText.indexOf(${JSON.stringify(texto)}) !== -1`,
      returnByValue: true,
    });
    if (result.value) return;
    await new Promise(resolve => {
      setTimeout(resolve, intervaloMs);
    });
  }
  throw new Error(
    `Texto "${texto}" não apareceu depois de ${tentativas * intervaloMs}ms`
  );
}
