// Modelo de produto e de carrossel enviado pela CONVERSA (#1716, épico #1320).
// Tudo lido da estrutura do modelo da Meta (`components`), nunca do texto, e
// sem expressão regular. A conversa só oferece o que esta tela sabe completar:
//   um        → topo PRODUCT + botão SPM: 1 produto do catálogo;
//   varios    → botão MPM: até 30 produtos numa lista ("Ver itens");
//   carrossel → cartões com topo PRODUCT: de 2 a 10 produtos, um por cartão;
//   cartoes   → carrossel de FOTOS: um passo por cartão (foto + texto).
// Ficam de fora (o envio não teria como completar): topo com campo, oferta,
// cupom, botão de link com campo, carrossel de vídeo e o que a Meta inventar.
// O servidor confere de novo (Whatsapp::Templates::ConversationSendGuard).
import { pedidoDeProdutos } from '../helpers/produtosNaCampanha';

const maiusculo = valor => String(valor || '').toUpperCase();
const partesDe = item => item?.components || [];

export const componenteDe = (template, tipo) =>
  partesDe(template).find(item => maiusculo(item?.type) === tipo);

// Os nomes dos campos {{n}} (ou {{nome}}) de um texto, em ordem, sem repetir.
export const camposDoTexto = texto => {
  const nomes = [];
  const fonte = String(texto || '');
  let inicio = fonte.indexOf('{{');
  while (inicio >= 0) {
    const fim = fonte.indexOf('}}', inicio);
    if (fim < 0) break;
    const nome = fonte.slice(inicio + 2, fim).trim();
    if (nome && !nomes.includes(nome)) nomes.push(nome);
    inicio = fonte.indexOf('{{', fim);
  }
  return nomes;
};

const preenchido = valor => String(valor || '').trim() !== '';

// O texto com cada campo trocado pelo valor (campo vazio fica como está).
export const preencherTexto = (texto, valores = {}) =>
  camposDoTexto(texto).reduce(
    (resultado, nome) =>
      preenchido(valores[nome])
        ? resultado.split(`{{${nome}}}`).join(valores[nome])
        : resultado,
    String(texto || '')
  );

// O texto para a tela: campo preenchido com o valor; campo vazio com o rótulo
// do espaço ("[espaço 1]"), nunca com {{1}}.
export const comEspacos = (texto, valores, rotulo) =>
  camposDoTexto(texto).reduce(
    (resultado, nome) => resultado.split(`{{${nome}}}`).join(rotulo(nome)),
    preencherTexto(texto, valores)
  );

// O exemplo que a Meta guardou para o campo (para o "Ex.: ...").
export const exemploDoCampo = (componente, nome) => {
  const posicional = componente?.example?.body_text?.[0];
  if (posicional) return posicional[Number(nome) - 1] || '';
  const nomeados = componente?.example?.body_text_named_params || [];
  return nomeados.find(item => item.param_name === nome)?.example || '';
};

const BOTOES_FIXOS = ['QUICK_REPLY', 'PHONE_NUMBER'];
const BOTOES_DE_PRODUTO = ['SPM', 'MPM'];

// Botão que vai sem nada a preencher: resposta rápida, telefone, link sem campo.
const botaoFixo = botao => {
  const tipo = maiusculo(botao?.type);
  if (BOTOES_FIXOS.includes(tipo)) return true;
  return tipo === 'URL' && camposDoTexto(botao.url).length === 0;
};

const botoesCompletaveis = (item, extras = []) =>
  (item?.buttons || []).every(
    botao => botaoFixo(botao) || extras.includes(maiusculo(botao?.type))
  );

const topoDe = item => componenteDe(item, 'HEADER');

// Topo de texto sem campo (o título da lista no MPM).
const topoDeTextoFixo = topo =>
  maiusculo(topo?.format) === 'TEXT' && camposDoTexto(topo.text).length === 0;

const cartoesDe = template => componenteDe(template, 'CAROUSEL')?.cards || [];

const cartaoDeProdutoCompletavel = cartao =>
  partesDe(cartao).every(item => {
    const tipo = maiusculo(item?.type);
    if (tipo === 'HEADER') return maiusculo(item.format) === 'PRODUCT';
    if (tipo === 'BUTTONS') return botoesCompletaveis(item, BOTOES_DE_PRODUTO);
    return tipo === 'BODY' && camposDoTexto(item.text).length === 0;
  });

const cartaoDeFotoCompletavel = cartao =>
  maiusculo(topoDe(cartao)?.format) === 'IMAGE' &&
  partesDe(cartao).every(item => {
    const tipo = maiusculo(item?.type);
    if (tipo === 'BUTTONS') return botoesCompletaveis(item);
    return ['HEADER', 'BODY'].includes(tipo);
  });

// As partes de fora dos cartões: corpo, rodapé, botões e o topo permitido.
const restoCompletavel = (template, topoAceito) =>
  partesDe(template).every(item => {
    const tipo = maiusculo(item?.type);
    if (['BODY', 'FOOTER', 'CAROUSEL'].includes(tipo)) return true;
    if (tipo === 'HEADER') return topoAceito(item);
    if (tipo === 'BUTTONS') return botoesCompletaveis(item, BOTOES_DE_PRODUTO);
    return false;
  });

const produtosCompletaveis = (template, tipo) => {
  const topoAceito = item =>
    topoDeTextoFixo(item) ||
    (tipo === 'um' && maiusculo(item.format) === 'PRODUCT');
  if (!restoCompletavel(template, topoAceito)) return false;
  return (
    tipo !== 'carrossel' ||
    cartoesDe(template).every(cartaoDeProdutoCompletavel)
  );
};

const fotosCompletaveis = template => {
  const cartoes = cartoesDe(template);
  return (
    cartoes.length > 0 &&
    cartoes.every(cartaoDeFotoCompletavel) &&
    restoCompletavel(template, () => false)
  );
};

// 'um' | 'varios' | 'carrossel' | 'cartoes', ou '' (modelo comum ou um que a
// conversa não sabe completar).
export const tipoNaConversa = template => {
  const produtos = pedidoDeProdutos(template);
  if (produtos) {
    return produtosCompletaveis(template, produtos.tipo) ? produtos.tipo : '';
  }
  return fotosCompletaveis(template) ? 'cartoes' : '';
};

export const TIPOS_DE_PRODUTO = ['um', 'varios', 'carrossel'];
export const levaProdutos = tipo => TIPOS_DE_PRODUTO.includes(tipo);

// Cada cartão do carrossel de fotos como a tela usa.
export const cartoesDoModelo = template =>
  cartoesDe(template).map((cartao, indice) => {
    const corpo = componenteDe(cartao, 'BODY');
    return {
      indice,
      corpo,
      campos: camposDoTexto(corpo?.text),
      botoes: (componenteDe(cartao, 'BUTTONS')?.buttons || []).map(botao => ({
        tipo: maiusculo(botao.type),
        texto: botao.text,
      })),
    };
  });

// Campos do corpo ainda vazios (vazio = pode enviar).
export const faltaNoCorpo = (template, valores) =>
  camposDoTexto(componenteDe(template, 'BODY')?.text).filter(
    nome => !preenchido(valores?.[nome])
  );

// valor = { imagem (miniatura), referencia (arquivo), nome, campos }
export const cartaoPronto = (cartao, valor) =>
  preenchido(valor?.referencia) &&
  cartao.campos.every(nome => preenchido(valor?.campos?.[nome]));

// O campo do perfil do modelo que o contato da conversa preenche sozinho,
// como na campanha (TemplateFields::ContactResolver). Nome que é só telefone
// não vale (contato do WhatsApp sem nome): nunca "Oi, +55 11 9…".
const SO_TELEFONE = '+0123456789 ()-';
const nomeDeVerdade = nome => {
  const limpo = String(nome || '').trim();
  return [...limpo].some(char => !SO_TELEFONE.includes(char)) ? limpo : '';
};
const LEITORES_DO_CONTATO = {
  'cliente.primeiro_nome': contato =>
    nomeDeVerdade(contato?.name).split(' ')[0],
  nome_cliente: contato => nomeDeVerdade(contato?.name).split(' ')[0],
  'cliente.nome': contato => nomeDeVerdade(contato?.name),
  'cliente.email': contato => String(contato?.email || '').trim(),
};

// { campo: valor } dos campos do corpo que o contato preenche.
export const camposDoContato = (template, perfil, contato) =>
  Object.fromEntries(
    camposDoTexto(componenteDe(template, 'BODY')?.text).flatMap(nome => {
      const ler = LEITORES_DO_CONTATO[perfil?.[nome]];
      const valor = ler ? ler(contato) : '';
      return valor ? [[nome, valor]] : [];
    })
  );

// A ordem dos vários produtos: a dos toques; subir e descer trocam vizinhos.
export const moverProduto = (lista, posicao, passo) => {
  const destino = posicao + passo;
  if (destino < 0 || destino >= lista.length) return lista;
  const copia = [...lista];
  [copia[posicao], copia[destino]] = [copia[destino], copia[posicao]];
  return copia;
};

// Os produtos com a disponibilidade relida do catálogo (o que não voltou
// saiu do catálogo e conta como acabado).
export const comEstoqueRelido = (produtos, relidos) => {
  const porId = Object.fromEntries(relidos.map(item => [item.id, item]));
  return produtos.map(produto => ({
    ...produto,
    disponivel: Boolean(porId[produto.id]?.disponivel),
  }));
};

// O pedido de envio da conversa: o mesmo `processed_params` da campanha
// (produtos do ProductParams; cartões com o arquivo escolhido, `media_blob`).
// O servidor completa o catálogo e o link de cada foto, e grava a foto do
// envio (`enviado`, #1717).
export const montarEnvio = ({ template, tipo, corpo, produtos, cartoes }) => {
  const processed = { body: { ...corpo } };
  if (levaProdutos(tipo)) {
    processed.products = {
      retailer_ids: produtos.map(produto => produto.id),
      names: Object.fromEntries(produtos.map(item => [item.id, item.nome])),
    };
  }
  if (tipo === 'cartoes') {
    processed.carousel = {
      cards: cartoesDoModelo(template).map(cartao => {
        const valor = cartoes[cartao.indice] || {};
        return {
          header: { media_blob: valor.referencia },
          body: { ...(valor.campos || {}) },
        };
      }),
    };
  }
  const texto = preencherTexto(componenteDe(template, 'BODY')?.text, corpo);
  return {
    message: texto,
    pendingMessageContent: texto,
    templateParams: {
      name: template.name,
      category: template.category,
      language: template.language,
      namespace: template.namespace,
      content_mode: 'raw_template',
      processed_params: processed,
    },
  };
};
