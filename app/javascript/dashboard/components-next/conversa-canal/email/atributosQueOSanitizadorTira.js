// O que o lettersanitizer 1.0.8 descarta e o Gmail mantém (#1916), devolvido sem abrir
// brecha: o sanitizador só aceita poucos atributos por tag (constants.js dele) e não
// recebe lista própria. Antes da limpeza o atributo vira algo que ele aceita; depois,
// volta ao lugar. Lê a estrutura (DOM), sem regex.
//
// - <hr style> e <hr class>: o <hr> só pode ter align, size e width. Vira uma <div> com
//   o estilo (que o sanitizador limpa como qualquer outro CSS) e volta a ser <hr>.
// - valign em <thead>, <tbody> e <tfoot>: não é aceito ali; desce para cada <tr> que não
//   tem o seu (o navegador alinha a célula pela linha).
// - <a name>: não é aceito; vira id, que é (e a âncora #nome volta a achar o destino).

const SECOES_DA_TABELA = 'thead[valign], tbody[valign], tfoot[valign]';
const ATRIBUTOS_DO_HR = ['align', 'size', 'width'];

const marcaAleatoria = () => `c2y${Math.random().toString(36).slice(2, 10)}`;

const valignNasLinhas = doc => {
  doc.body.querySelectorAll(SECOES_DA_TABELA).forEach(secao => {
    const valor = secao.getAttribute('valign');
    [...secao.children].forEach(linha => {
      if (linha.tagName === 'TR' && !linha.hasAttribute('valign'))
        linha.setAttribute('valign', valor);
    });
  });
};

const nomeComoId = doc => {
  doc.body.querySelectorAll('a[name]').forEach(ancora => {
    const nome = ancora.getAttribute('name').trim();
    if (nome && !ancora.id) ancora.id = nome;
  });
};

// Cada <hr> vira <div id="marca-N"> com o estilo e a classe dele; os atributos que o
// <hr> aceita ficam guardados para voltar.
const hrComoDiv = (doc, marca) =>
  [...doc.body.querySelectorAll('hr')].map((hr, indice) => {
    const div = doc.createElement('div');
    div.id = `${marca}-${indice}`;
    ['style', 'class'].forEach(nome => {
      if (hr.hasAttribute(nome)) div.setAttribute(nome, hr.getAttribute(nome));
    });
    const guardados = ATRIBUTOS_DO_HR.filter(nome => hr.hasAttribute(nome)).map(
      nome => [nome, hr.getAttribute(nome)]
    );
    hr.replaceWith(div);
    return guardados;
  });

const divComoHr = (doc, marca, guardados) => {
  guardados.forEach((atributos, indice) => {
    const div = doc.getElementById(`${marca}-${indice}`);
    if (!div) return;
    const hr = doc.createElement('hr');
    ['style', 'class'].forEach(nome => {
      if (div.hasAttribute(nome)) hr.setAttribute(nome, div.getAttribute(nome));
    });
    atributos.forEach(([nome, valor]) => hr.setAttribute(nome, valor));
    div.replaceWith(hr);
  });
};

// Chama antes do sanitizador, no documento original; devolve o que chamar depois, no
// documento limpo.
export const antesDaLimpeza = doc => {
  valignNasLinhas(doc);
  nomeComoId(doc);
  const marca = marcaAleatoria();
  const guardados = hrComoDiv(doc, marca);
  return limpo => divComoHr(limpo, marca, guardados);
};
