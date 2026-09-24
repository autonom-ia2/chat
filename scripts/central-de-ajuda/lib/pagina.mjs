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
    '#mini-profiler, .profiler-results{display:none!important;}' +
    /* Borra o texto de marca que está colado no próprio botão/frase (ex.
       "seu painel do Autonom.ia") — recorte não resolve quando a marca está
       dentro do alvo que a cena precisa mostrar. */
    '.__gravacao-desfoque{filter:blur(6px)!important;}';
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
  //
  // Só entram candidatos VISÍVEIS: o painel tem texto repetido escondido no
  // DOM (paleta de comando, itens de menu recolhidos) que bate com o mesmo
  // texto de um alvo real e visível na tela. Sem filtrar aqui, um candidato
  // escondido podia ganhar da ordenação por especificidade/tamanho, e o
  // motor esperava para sempre um elemento que nunca ia aparecer.
  // 'raiz' opcional: busca só dentro desse elemento em vez da página
  // inteira. Sem argumento, o comportamento é idêntico ao de sempre.
  function encontrarPorTexto(texto, raiz) {
    var escopo = raiz || document.body;
    var candidatos = Array.prototype.filter.call(
      escopo.querySelectorAll('*'),
      function (n) {
        return (
          n.textContent && n.textContent.trim() === texto && elementoVisivel(n)
        );
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

  // 'spec.dentro' (opcional, mesma forma de um alvo, mais 'subindoAte')
  // restringe a busca por texto a dentro do elemento achado por esse alvo —
  // útil quando o mesmo rótulo se repete em várias linhas de uma
  // lista/tabela de configurações (ex.: um checkbox "CRM ativo" por caixa de
  // entrada) e só o texto de uma linha vizinha (o nome daquela caixa)
  // distingue qual é a certa. 'encontrarPorTexto' sempre acha o elemento mais
  // ESPECÍFICO (mais interno); para virar um contêiner de linha inteira,
  // 'dentro.subindoAte' sobe até o ancestral mais próximo que bate com esse
  // seletor CSS (ex.: 'section', 'tr', 'li') antes de buscar o texto do alvo
  // lá dentro.
  function encontrarElemento(spec) {
    if (spec.seletor) return document.querySelector(spec.seletor);
    if (spec.texto) {
      if (spec.dentro) {
        var alvoDentro = encontrarElemento(spec.dentro);
        if (!alvoDentro) return null;
        var container = spec.dentro.subindoAte
          ? alvoDentro.closest(spec.dentro.subindoAte)
          : alvoDentro;
        if (!container) return null;
        return encontrarPorTexto(spec.texto, container);
      }
      return encontrarPorTexto(spec.texto);
    }
    return null;
  }

  // O centro geométrico do alvo às vezes fica embaixo de outra coisa fixa
  // na tela (ex.: o botão flutuante do Guia da Plataforma, sempre no canto
  // inferior — cobre o canto de um botão de formulário que termine ali
  // perto). Clicar nesse ponto clica no que está por cima, não no alvo, e
  // o roteiro segue como se tivesse funcionado (sem erro nenhum, só nada
  // acontece). Por isso: confere se o ponto é mesmo clicável nesse alvo e,
  // se não for, tenta outros pontos dentro do mesmo retângulo antes de
  // desistir e usar o centro de qualquer jeito.
  function pontoClicavel(el, r) {
    function usavel(x, y) {
      var noPonto = document.elementFromPoint(x, y);
      return (
        !!noPonto &&
        (noPonto === el || el.contains(noPonto) || noPonto.contains(el))
      );
    }
    var candidatos = [
      [r.left + r.width / 2, r.top + r.height / 2],
      [r.left + r.width * 0.25, r.top + r.height / 2],
      [r.left + r.width * 0.75, r.top + r.height / 2],
      [r.left + r.width / 2, r.top + r.height * 0.25],
      [r.left + r.width / 2, r.top + r.height * 0.75],
    ];
    for (var i = 0; i < candidatos.length; i += 1) {
      var x = candidatos[i][0];
      var y = candidatos[i][1];
      if (usavel(x, y)) return { x: x, y: y };
    }
    return { x: candidatos[0][0], y: candidatos[0][1] };
  }

  function achar(spec) {
    var el = encontrarElemento(spec);
    if (!elementoVisivel(el)) return null;
    var r = el.getBoundingClientRect();
    var ponto = pontoClicavel(el, r);
    return {
      x: r.left,
      y: r.top,
      width: r.width,
      height: r.height,
      centroX: ponto.x,
      centroY: ponto.y,
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

// 15s de orçamento padrão (era 4s): com várias gravações rodando ao mesmo
// tempo, até um clique simples (abrir um menu) pode demorar mais que 4s de
// CPU disputada — o mesmo motivo que já tinha levado esperarTexto/
// aguardarTextoDepois para 30s. Continua rápido quando o alvo aparece logo
// (o loop sai assim que acha); só o caminho de erro fica mais paciente.
async function achar(
  cliente,
  alvo,
  { tentativas = 100, intervaloMs = 150 } = {}
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

// Arrasta o cursor de (origemX,origemY) até (destinoX,destinoY) com o botão
// esquerdo pressionado — para mover um card entre colunas do Kanban
// (vuedraggable/sortable.js). Não reaproveita `dispatchMouse`: sortable.js
// só detecta arrasto quando os eventos 'mousemove' no meio do caminho já
// carregam `buttons: 1` (botão ainda pressionado), e `dispatchMouse` zera
// `buttons` em qualquer evento que não seja 'mousePressed' — certo para um
// simples mover-e-clicar, errado para arrastar.
export async function arrastar(
  cliente,
  origemX,
  origemY,
  destinoX,
  destinoY,
  duracaoMs = 900
) {
  async function evento(type, x, y, buttons) {
    await cliente.enviar('Input.dispatchMouseEvent', {
      type,
      x,
      y,
      button: 'left',
      buttons,
      clickCount: type === 'mousePressed' ? 1 : 0,
    });
  }
  await evento('mouseMoved', origemX, origemY, 0);
  await evento('mousePressed', origemX, origemY, 1);
  await new Promise(resolve => {
    setTimeout(resolve, 80); // dá tempo do sortable registrar o "pegar" antes de mover
  });
  const passos = Math.max(10, Math.round(duracaoMs / 20));
  for (let i = 1; i <= passos; i += 1) {
    const t = i / passos;
    const x = origemX + (destinoX - origemX) * t;
    const y = origemY + (destinoY - origemY) * t;
    // eslint-disable-next-line no-await-in-loop -- cada passo do arrasto depende do anterior
    await evento('mouseMoved', x, y, 1);
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, duracaoMs / passos);
    });
  }
  await evento('mouseMoved', destinoX, destinoY, 1);
  await new Promise(resolve => {
    setTimeout(resolve, 80); // dá tempo do sortable reconhecer o alvo antes de soltar
  });
  await evento('mouseReleased', destinoX, destinoY, 0);
  posicaoAtual = { x: destinoX, y: destinoY };
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

// Limpa o campo focado ANTES de digitar (uso opcional da ação "digitar" via
// `cena.limparAntes: true`) — para campo de texto simples (<input>/
// <textarea>) que já nasce preenchido, como o nome do funil no CRM Kanban
// (vem com um valor padrão) ou qualquer campo de edição com valor existente.
// Só mexe em elementos com `.value` (inputs nativos); num editor rico
// (ProseMirror, sem `.value`) não faz nada — digitar ali sempre parte de
// campo vazio nos roteiros de hoje, então não precisa de tratamento ainda.
export async function limparCampo(cliente) {
  const { result } = await cliente.enviar('Runtime.evaluate', {
    expression: `
      (function () {
        var el = document.activeElement;
        if (!el || !('value' in el)) return false;
        el.value = '';
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      })()
    `,
    returnByValue: true,
  });
  return Boolean(result.value);
}

// Define o valor do campo focado pelo setter nativo do input, não por
// `Input.insertText` — para campos que não aceitam digitação simulada por
// texto (ex. `input[type="datetime-local"]`, `type="date"`, `type="color"`,
// `type="range"`). Usa a ação "definirValor" do roteiro (alvo + `valor`):
// clica no alvo (como "digitar" já faz) e chama isto em vez de
// `digitarLinhas`. Dispara `input`/`change` do jeito que o Vue espera de um
// v-model — mesmo princípio do `limparCampo` acima, só que escrevendo um
// valor em vez de esvaziar.
export async function definirValor(cliente, valor) {
  const { result } = await cliente.enviar('Runtime.evaluate', {
    expression: `
      (function () {
        var el = document.activeElement;
        if (!el || !('value' in el)) return false;
        var setter = Object.getOwnPropertyDescriptor(
          Object.getPrototypeOf(el),
          'value'
        );
        if (setter && setter.set) {
          setter.set.call(el, ${JSON.stringify(valor)});
        } else {
          el.value = ${JSON.stringify(valor)};
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      })()
    `,
    returnByValue: true,
  });
  return Boolean(result.value);
}

// Escolhe uma opção de um <select> nativo pelo valor OU pelo texto visível
// da opção. Um <option> não tem retângulo próprio de layout (o navegador
// desenha a lista fora da árvore normal), então não dá para "clicar" nele
// como em qualquer outro alvo — em vez disso clica no <select> (igual a
// "digitar" clica no campo antes de escrever) e troca o valor pelo setter
// nativo, disparando 'input'/'change' do jeito que o Vue espera de um
// v-model. Usa a ação "selecionar" do roteiro (alvo + `valor`).
export async function selecionar(cliente, valorOuTexto) {
  const { result } = await cliente.enviar('Runtime.evaluate', {
    expression: `
      (function () {
        var el = document.activeElement;
        if (!el || el.tagName !== 'SELECT') return false;
        var alvo = ${JSON.stringify(valorOuTexto)};
        var opcao = Array.prototype.find.call(el.options, function (o) {
          return o.value === alvo || o.textContent.trim() === alvo;
        });
        if (!opcao) return false;
        var setter = Object.getOwnPropertyDescriptor(
          Object.getPrototypeOf(el),
          'value'
        );
        if (setter && setter.set) {
          setter.set.call(el, opcao.value);
        } else {
          el.value = opcao.value;
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      })()
    `,
    returnByValue: true,
  });
  return Boolean(result.value);
}

// Seletor do painel (ChoiceSelect, role="combobox"; o painel não tem mais
// <select> nativo, #652): depois do clique no campo a lista abre de verdade,
// então o vídeo mostra a lista e o cursor clica na opção, como uma pessoa.
// Acha a opção pelo data-value (valor) ou pelo texto visível e devolve o
// retângulo dela. Devolve null quando o foco não está num combobox — aí o
// alvo é um <select> nativo e vale selecionar(). Opção inexistente é erro.
export async function acharOpcaoDoCombobox(
  cliente,
  valorOuTexto,
  { tentativas = 20, intervaloMs = 100 } = {}
) {
  for (let i = 0; i < tentativas; i += 1) {
    const { result } = await cliente.enviar('Runtime.evaluate', {
      expression: `
        (function () {
          var campo = document.activeElement;
          if (!campo || campo.getAttribute('role') !== 'combobox') return null;
          var lista = document.getElementById(campo.getAttribute('aria-controls'));
          if (!lista) return { pronta: false };
          // data-value é sempre texto (String do valor): 7, null e true do
          // roteiro viram '7', 'null' e 'true' para comparar.
          var alvo = String(${JSON.stringify(valorOuTexto)});
          var opcao = Array.prototype.find.call(
            lista.querySelectorAll('[role="option"]'),
            function (o) {
              return o.dataset.value === alvo || o.textContent.trim() === alvo;
            }
          );
          if (!opcao) return { pronta: true, achou: false };
          opcao.scrollIntoView({ block: 'nearest' });
          var r = opcao.getBoundingClientRect();
          if (!r.width || !r.height) return { pronta: false };
          return {
            pronta: true,
            achou: true,
            x: r.left,
            y: r.top,
            width: r.width,
            height: r.height,
            centroX: r.left + r.width / 2,
            centroY: r.top + r.height / 2,
          };
        })()
      `,
      returnByValue: true,
    });
    const achado = result.value;
    if (achado === null) return null;
    if (achado.pronta && !achado.achou) {
      throw new Error(`Opção não encontrada no seletor: ${valorOuTexto}`);
    }
    if (achado.achou) return achado;
    await new Promise(resolve => {
      setTimeout(resolve, intervaloMs);
    });
  }
  throw new Error(`A lista do seletor não abriu para escolher: ${valorOuTexto}`);
}

// Anexa um arquivo local a um <input type="file"> — mesmo escondido atrás
// de um botão/label visível (padrão comum: o botão dispara input.click(),
// e o input real fica com display:none ou 1x1px). Não dá para simular o
// seletor de arquivo do sistema operacional por clique; o CDP resolve isso
// direto, via DOM.setFileInputFiles, que dispara o 'change' que o Vue
// espera do mesmo jeito que uma escolha manual dispararia. `seletorInput` é
// sempre um seletor CSS (arquivo não tem texto visível para casar por
// alvo.texto). O cursor/destaque do roteiro ficam no botão visível — isso é
// responsabilidade do `cena.alvo` de sempre, não desta função.
export async function anexarArquivo(cliente, seletorInput, caminhoArquivo) {
  await cliente.enviar('DOM.enable');
  const { root } = await cliente.enviar('DOM.getDocument', {
    depth: -1,
    pierce: true,
  });
  const { nodeId } = await cliente.enviar('DOM.querySelector', {
    nodeId: root.nodeId,
    selector: seletorInput,
  });
  if (!nodeId) {
    throw new Error(
      `anexarArquivo: nenhum elemento para o seletor "${seletorInput}"`
    );
  }
  await cliente.enviar('DOM.setFileInputFiles', {
    files: [caminhoArquivo],
    nodeId,
  });
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
          // Já desfocado por 'desfocarMarcasVisiveis' — não conta como
          // marca visível.
          if (no.parentElement && no.parentElement.closest('.__gravacao-desfoque')) {
            continue;
          }
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

// Borra (filter: blur) o menor elemento visível que contém um termo de
// marca — para quando a frase está colada no próprio alvo da cena (ex. o
// botão "Alterar Tema" cuja descrição diz "seu painel do Autonom.ia"), onde
// recortar o zoom para fora do texto não é possível. Ligado por padrão
// (roteiro pode desligar com `export const desfocarMarca = false`);
// chamada nos mesmos pontos de 'esperarSemCarregando' — antes de gravar e
// depois de cada navegação. O menor elemento que contém o texto é sempre o
// parentElement do próprio nó de texto (um nó de texto só tem um pai).
export async function desfocarMarcasVisiveis(cliente) {
  await cliente.enviar('Runtime.evaluate', {
    expression: `
      (function () {
        var termos = ${JSON.stringify(TERMOS_PROIBIDOS)};
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var no;
        while ((no = walker.nextNode())) {
          var texto = no.textContent;
          if (!texto) continue;
          var bate = false;
          for (var t = 0; t < termos.length; t += 1) {
            if (texto.indexOf(termos[t]) !== -1) {
              bate = true;
              break;
            }
          }
          if (!bate) continue;
          var el = no.parentElement;
          if (!el) continue;
          var r = el.getBoundingClientRect();
          if (r.width === 0 || r.height === 0) continue;
          el.classList.add('__gravacao-desfoque');
        }
        return true;
      })()
    `,
    returnByValue: true,
  });
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

// Espera sumir qualquer texto visível que COMECE com "Carregando" (sem
// regex — só startsWith no texto de cada nó, depois de trim). Usada pelo
// motor sozinha, não pelo roteiro: antes de começar a gravar (para o pôster
// — o primeiro quadro do vídeo — não pegar a tela "Carregando dados do
// gráfico…") e depois de cada navegação ("ir para" e "mover e clicar", que
// trocam de tela). Nunca falha: espera até ~10s (tentativas × intervaloMs)
// e, se ainda tiver "Carregando" na tela depois disso, segue em frente do
// mesmo jeito — é uma folga extra, não uma checagem que derruba a
// gravação.
export async function esperarSemCarregando(
  cliente,
  { tentativas = 50, intervaloMs = 200 } = {}
) {
  for (let i = 0; i < tentativas; i += 1) {
    const { result } = await cliente.enviar('Runtime.evaluate', {
      expression: `
        (function () {
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          var no;
          while ((no = walker.nextNode())) {
            var texto = no.textContent;
            if (!texto) continue;
            var t = texto.trim();
            if (!t || !t.startsWith('Carregando')) continue;
            var el = no.parentElement;
            if (!el) continue;
            var r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0) return true;
          }
          return false;
        })()
      `,
      returnByValue: true,
    });
    if (!result.value) return;
    await new Promise(resolve => {
      setTimeout(resolve, intervaloMs);
    });
  }
}
