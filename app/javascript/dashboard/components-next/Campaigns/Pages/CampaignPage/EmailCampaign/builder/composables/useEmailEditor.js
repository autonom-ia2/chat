// Singleton de modulo: UNICA fonte da verdade do editor de email.
// NINGUEM chama grapesjs.init fora daqui; NINGUEM acessa editor.value cru.
// Refs Backbone (editor/Block/Component/Sector/Property) sao shallowRef+markRaw.
// Contrato congelado em /tmp/uxshot/amendments.md §1.

import { ref, shallowRef, computed, markRaw } from 'vue';
import 'grapesjs/dist/css/grapes.min.css';

import registerAutonomiaBlocks from '../blocks';

// ---- estado interno (modulo) ----
const editor = shallowRef(null);
const isReady = ref(false);
const blocks = shallowRef([]);
const blockBus = shallowRef(null);
const selectedComponent = shallowRef(null);
const sectors = shallowRef([]);
const styleVersion = ref(0);
const device = ref('desktop');
const footerLocked = ref(false);

const DEVICE_MAP = { desktop: 'Desktop', mobile: 'Mobile portrait' };
let editorGeneration = 0;
let savedCanvasView = null;
let previewBodyObserver;
let previewGeneration = 0;
const PREVIEW_WIDTH = { desktop: 600, mobile: 320 };
const PREVIEW_GUTTER = 64;

const refreshSectors = () => {
  const ed = editor.value;
  if (!ed) {
    sectors.value = [];
    return;
  }
  const list = ed.StyleManager.getSectors({ visible: true });
  sectors.value = (list?.models || list || []).map(markRaw);
  styleVersion.value += 1;
};

const lockFooter = () => {
  const ed = editor.value;
  if (!ed) return;
  let locked = false;
  const lock = component => {
    component.set({ removable: false, draggable: false, copyable: false });
    locked = true;
  };
  const walk = component => {
    const cssClass =
      (component.getAttributes && component.getAttributes()['css-class']) || '';
    if (cssClass.includes('footer-locked')) lock(component);
    component.components?.().each(walk);
  };
  ed.getWrapper().components().each(walk);
  footerLocked.value = locked;
};

// MJML leaf/void tags that must NOT wrap siblings. grapesjs-mjml registers them with void:false,
// so a self-closed <mj-spacer/> is parsed by the HTML parser as an OPEN tag that swallows every
// following sibling; the MJML compiler then DROPS that nested content (the whole body arrives
// hollow). Forcing an explicit empty close keeps them as leaves so the getMjml/getHtml round-trip
// stays flat and the rendered/sent e-mail matches the canvas. Applied on every setComponents input.
const VOID_MJML_TAGS = ['mj-spacer', 'mj-divider', 'mj-image'];
const normalizeVoidMjml = (mjml = '') =>
  VOID_MJML_TAGS.reduce(
    (acc, tag) =>
      acc.replace(
        new RegExp(
          `<${tag}(?=[\\s/>])((?:[^>"']|"[^"]*"|'[^']*')*?)\\s*/>`,
          'gi'
        ),
        `<${tag}$1></${tag}>`
      ),
    mjml
  );

async function init(el, opts = {}) {
  // Idempotente: ja inicializado -> devolve a instancia existente (evita 2o
  // editor / leak quando o componente re-monta).
  if (editor.value) return editor.value;

  const generation = editorGeneration + 1;
  editorGeneration = generation;
  if (!el?.isConnected) return null;

  const [{ default: grapesjs }, { default: mjmlPlugin }] = await Promise.all([
    import('grapesjs'),
    import('grapesjs-mjml'),
  ]);

  if (generation !== editorGeneration || !el.isConnected) return null;

  const ed = grapesjs.init({
    container: el,
    height: '100%',
    fromElement: false,
    storageManager: false,
    panels: { defaults: [] },
    blockManager: { custom: true },
    styleManager: { custom: true },
    // assetManager.custom => o modal feio/ingles do GrapesJS NUNCA renderiza.
    // Nosso PropImage.vue cuida do upload/troca de imagem.
    assetManager: { custom: true },
    plugins: [mjmlPlugin],
    pluginsOpts: {
      [mjmlPlugin]: { useCustomTheme: false, blocks: [] },
    },
  });

  if (generation !== editorGeneration || !el.isConnected) {
    ed.destroy();
    return null;
  }

  editor.value = markRaw(ed);

  // Blocos via block:custom -> ref reativo de cards + bus de drag nativo.
  ed.on('block:custom', props => {
    blockBus.value = markRaw(props);
    blocks.value = (props.blocks || []).map(markRaw);
  });

  // Style Manager headless: re-render do painel de props.
  ed.on('style:custom', refreshSectors);
  ed.on('component:selected', cmp => {
    selectedComponent.value = markRaw(cmp);
    refreshSectors();
  });
  ed.on('component:deselected', () => {
    selectedComponent.value = null;
    refreshSectors();
  });
  ed.on('component:add', lockFooter);

  ed.BlockManager.getAll?.()?.reset?.();
  registerAutonomiaBlocks(ed);

  // Caminho `ready` UNICO. O grapesjs-mjml registra os setores do StyleManager
  // dentro de editor.onReady(); so depois disso getProperty resolve. Por isso
  // tudo que depende do editor "pronto" roda aqui, uma unica vez.
  const onReady = () => {
    // belt-and-suspenders dos blocos: em blockManager.custom o `block:custom`
    // e disparado de forma debounced ao adicionar blocos. ed.BlockManager
    // .render() forca o pipeline; e, caso o listener ainda nao tenha populado
    // `blocks` (corrida de debounce), semeamos direto do BlockManager.
    ed.BlockManager.render();
    if (!blocks.value.length) {
      const bm = ed.BlockManager;
      blocks.value = (bm.getAll?.()?.models || []).map(markRaw);
    }
    lockFooter();
    isReady.value = true;
  };

  const initialMjml = opts.mjml || '';
  if (initialMjml) {
    ed.setComponents(normalizeVoidMjml(initialMjml));
  }

  // onReady dispara imediatamente se o editor ja estiver pronto, ou agenda.
  // Idempotente do nosso lado (so chamamos uma vez).
  ed.onReady(onReady);

  return ed;
}

function destroy() {
  editorGeneration += 1;
  previewGeneration += 1;
  previewBodyObserver?.disconnect();
  editor.value?.destroy();
  editor.value = null;
  isReady.value = false;
  blocks.value = [];
  blockBus.value = null;
  selectedComponent.value = null;
  sectors.value = [];
  styleVersion.value = 0;
  device.value = 'desktop';
  footerLocked.value = false;
  savedCanvasView = null;
}

// ---- BLOCKS ----
const dragStart = (block, ev) => blockBus.value?.dragStart(block, ev);
const dragStop = cancel => blockBus.value?.dragStop(cancel);

// ---- PROPS / STYLE ----
// CAUSA-RAIZ DO WRITE-BACK: o grapesjs-mjml registra os setores com `name`
// ('Dimension'|'Typography'|'Decorations') mas SEM `id`. O Sector model deriva
// o id de `name.replace(/ /g,'_').toLowerCase()` (grapesjs/.../model/Sector.ts),
// logo os ids reais sao 'dimension'|'typography'|'decorations'. StyleManager
// .getProperty(sectorId) faz `sectors.where({ id: sectorId })` — match EXATO,
// case-sensitive. Chamar getProperty('Typography','color') retornava undefined,
// entao upValue nunca era invocado e o canvas nao mudava.
// Normalizamos o sectorId aqui (downcase) mantendo o contrato §1 (ids
// capitalizados) intacto p/ os consumidores.
const normalizeSectorId = sectorId =>
  typeof sectorId === 'string' ? sectorId.toLowerCase() : sectorId;

const getProperty = (sectorId, propName) =>
  editor.value?.StyleManager.getProperty(normalizeSectorId(sectorId), propName);

const upValue = (prop, value, opts = {}) => {
  let property = prop;
  if (Array.isArray(prop)) property = getProperty(prop[0], prop[1]);
  // upValue propaga p/ os targets selecionados (StyleManager segue o
  // component:selected automaticamente via component:toggled). Nao precisamos
  // de StyleManager.setTarget/select manual: addStyleTargets le getSelectedAll()
  // no momento da escrita.
  return property?.upValue(value, opts);
};

// ---- ESTILOS ROBUSTOS (sector property OU style direto) ----
// font-style/text-decoration podem NAO estar registrados como properties de
// setor. Tentamos a property (getValue/upValue) e caimos no getStyle/addStyle do
// componente selecionado, que tambem re-renderiza o canvas.
const getStyleProp = (sectorId, propName) => {
  const property = getProperty(sectorId, propName);
  if (property) return property.getValue({ noDefault: true }) ?? '';
  const cmp = editor.value?.getSelected();
  return cmp?.getStyle?.()?.[propName] ?? '';
};

const applyStyleProp = (sectorId, propName, value) => {
  const property = getProperty(sectorId, propName);
  if (property) {
    property.upValue(value);
    return;
  }
  const cmp = editor.value?.getSelected();
  cmp?.addStyle?.({ [propName]: value });
};

// ---- ATRIBUTOS DO COMPONENTE SELECIONADO (img: src/alt/href) ----
const getSelectedAttribute = name =>
  editor.value?.getSelected()?.getAttributes?.()?.[name];

// O mj-image do grapesjs-mjml exporta o src lendo a PROPRIEDADE do modelo
// (`getMjmlAttributes`: `e=this.get('src'); e&&(t.src=e)`) — ela SOBRESCREVE o
// atributo. Logo `addAttributes({src})` sozinho nunca vinga (o getMjml/getHtml
// reusa o src antigo do modelo). Para src precisamos setar a propriedade do
// modelo tambem; href e demais atributos persistem via atributo normal.
const writeSelected = (cmp, name, value) => {
  if (name === 'src') cmp.set?.('src', value);
  cmp.addAttributes?.({ [name]: value });
};

const setSelectedAttribute = (name, value) => {
  const cmp = editor.value?.getSelected();
  if (cmp) writeSelected(cmp, name, value);
};

// Grava VARIOS atributos de uma vez. Dois setSelectedAttribute consecutivos
// disparam dois re-renders e o segundo descarta a escrita do primeiro (ex.: src +
// href ao resolver o video). Aplica a mesma regra de modelo do src.
const setSelectedAttributes = attrs => {
  const cmp = editor.value?.getSelected();
  if (!cmp) return;
  if ('src' in attrs) cmp.set?.('src', attrs.src);
  cmp.addAttributes?.({ ...attrs });
};

// ---- FUNDO DO BLOCO (secao ancestral) ----
// O "Fundo" que o usuario quer ver/editar e a cor do BLOCO visivel — a mj-section
// ancestral (a faixa colorida) — e nao o container-background-color (muitas vezes
// vazio) do proprio elemento. Caminha ate a mj-section mais proxima e le/grava o
// background-color dela; grapesjs-mjml mapeia esse style -> atributo, re-renderiza
// e sobrevive ao getMjml/getHtml.
const ancestorSection = () => {
  let cmp = editor.value?.getSelected();
  while (cmp) {
    if (cmp.get?.('type') === 'mj-section') return cmp;
    cmp = cmp.parent?.();
  }
  return null;
};

// grapesjs-mjml stores mj-section background-color as an ATTRIBUTE; depending on
// the version it may or may not mirror into the component style. Read both so the
// control reflects the real current value.
const getSectionStyle = propName => {
  const section = ancestorSection();
  if (!section) return '';
  return (
    section.getStyle?.()?.[propName] ||
    section.getAttributes?.()?.[propName] ||
    ''
  );
};

// Write via BOTH style (re-renders the canvas) and attribute (what mj-section
// serializes to MJML), so the change is visible AND survives getMjml/getHtml.
const setSectionStyle = (propName, value) => {
  const section = ancestorSection();
  if (!section) return;
  section.addStyle?.({ [propName]: value });
  section.addAttributes?.({ [propName]: value });
};

// Tipo do componente selecionado. grapesjs-mjml usa 'mj-image' p/ imagens.
const selectedType = computed(() => selectedComponent.value?.get?.('type'));

// ---- TOP BAR / COMANDOS ----
const runCommand = (name, opts) => editor.value?.runCommand(name, opts);

const setDevice = d => {
  const target = DEVICE_MAP[d] || DEVICE_MAP.desktop;
  editor.value?.setDevice(target);
  device.value = d === 'mobile' ? 'mobile' : 'desktop';
};

// GrapesJS owns its iframe geometry and zoom; never scale the editor with CSS.
const setCanvasPreview = async (fullView, fitToView = true) => {
  const ed = editor.value;
  if (!ed) return;
  previewGeneration += 1;
  const generation = previewGeneration;
  previewBodyObserver?.disconnect();
  const canvas = ed.Canvas;
  const frame = canvas.getFrame();
  const frameWindow = canvas.getWindow();
  if (!fullView) {
    if (!savedCanvasView) return;
    ed.stopCommand('preview');
    frame.set({ width: savedCanvasView.width, height: savedCanvasView.height });
    canvas.setZoom(savedCanvasView.zoom);
    canvas.setCoords(savedCanvasView.x, savedCanvasView.y);
    const { scrollX, scrollY, viewportHeight } = savedCanvasView;
    savedCanvasView = null;
    // Restoring scroll while the frame is shrinking clamps it to the old
    // viewport. Restore after resize until the original viewport is reached.
    previewBodyObserver = new ResizeObserver(() => {
      if (generation !== previewGeneration || ed !== editor.value) return;
      frameWindow.scrollTo(scrollX, scrollY);
      if (frameWindow.innerHeight <= viewportHeight) {
        previewBodyObserver.disconnect();
      }
    });
    previewBodyObserver.observe(canvas.getFrameEl());
    return;
  }
  if (!savedCanvasView) {
    savedCanvasView = {
      width: frame.get('width'),
      height: frame.get('height'),
      zoom: canvas.getZoom(),
      ...canvas.getCoords(),
      scrollX: frameWindow.scrollX,
      scrollY: frameWindow.scrollY,
      viewportHeight: frameWindow.innerHeight,
    };
    ed.runCommand('preview');
  }
  const width = PREVIEW_WIDTH[device.value];
  frame.set({ width, height: '' });
  canvas.setCoords(0, 0);
  frameWindow.scrollTo(0, 0);
  await new Promise(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  });
  if (generation !== previewGeneration || ed !== editor.value) return;
  // MJML wrappers have min-height: 100vh. Observing/auto-sizing them feeds the
  // iframe height back into itself; measure the rendered email inside instead.
  const content = canvas
    .getBody()
    .querySelector('[data-gjs-type="mj-body"]').firstElementChild;
  const updateZoom = () => {
    if (generation !== previewGeneration || ed !== editor.value) return;
    if (fitToView) {
      const height = Math.ceil(
        content.getBoundingClientRect().bottom +
          frameWindow.scrollY +
          PREVIEW_GUTTER / 2
      );
      frame.set({ height });
      canvas.fitViewport({
        el: content,
        gap: PREVIEW_GUTTER / 2,
        zoom: zoom => Math.min(100, zoom),
      });
    } else {
      canvas.setZoom(100);
    }
  };
  updateZoom();
  if (fitToView) {
    previewBodyObserver = new ResizeObserver(updateZoom);
    previewBodyObserver.observe(content);
  }
};

const subscribeCanvasScroll = callback => {
  const ed = editor.value;
  let frameWindow;
  const onScroll = () => callback(frameWindow.scrollY);
  const bind = ({ window: loadedWindow } = {}) => {
    frameWindow?.removeEventListener('scroll', onScroll);
    frameWindow = loadedWindow || ed.Canvas.getWindow();
    frameWindow.addEventListener('scroll', onScroll, { passive: true });
  };
  ed.on('canvas:frame:load', bind);
  if (ed.Canvas.getBody()) bind();
  return () => {
    frameWindow?.removeEventListener('scroll', onScroll);
    ed.off('canvas:frame:load', bind);
  };
};
const adjustCanvasScroll = delta =>
  editor.value?.Canvas.getWindow().scrollBy(0, delta);

// ---- I/O MJML/HTML ----
const getMjml = () => editor.value?.runCommand('mjml-code') || '';

const getHtml = () => {
  const out = editor.value?.runCommand('mjml-code-to-html') || {};
  if (out.errors?.length) {
    // eslint-disable-next-line no-console
    console.warn('[useEmailEditor] mjml-code-to-html errors', out.errors);
  }
  return out.html || '';
};

const setMjml = mjml => {
  editor.value?.setComponents(normalizeVoidMjml(mjml));
  lockFooter();
};

// ---- selecao/texto ----
const getSelectedText = () => {
  const cmp = selectedComponent.value || editor.value?.getSelected();
  if (!cmp) return '';
  return cmp.getEl?.()?.innerText ?? cmp.getInnerHTML?.() ?? '';
};

const setSelectedText = html => {
  const cmp = selectedComponent.value || editor.value?.getSelected();
  if (!cmp) return;
  cmp.components(html);
};

export function useEmailEditor() {
  return {
    // refs reativos (somente leitura p/ consumidores)
    editor,
    isReady,
    blocks,
    selectedComponent,
    selectedType,
    sectors,
    styleVersion,
    device,
    footerLocked,

    // ciclo de vida (SO o GrapesEditor.vue chama)
    init,
    destroy,

    // BLOCKS
    dragStart,
    dragStop,

    // PROPS / STYLE
    getProperty,
    upValue,
    getStyleProp,
    applyStyleProp,

    // ATRIBUTOS (img src/alt/href)
    getSelectedAttribute,
    setSelectedAttribute,
    setSelectedAttributes,

    // FUNDO DO BLOCO (mj-section ancestral)
    getSectionStyle,
    setSectionStyle,

    // TOP BAR / COMANDOS
    runCommand,
    setDevice,
    setCanvasPreview,
    subscribeCanvasScroll,
    adjustCanvasScroll,

    // I/O MJML/HTML
    getMjml,
    getHtml,
    setMjml,

    // LOCK
    lockFooter,

    // selecao/texto
    getSelectedText,
    setSelectedText,
  };
}

export default useEmailEditor;
