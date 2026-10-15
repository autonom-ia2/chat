// #1550 — pacotes de tradução por conta, compostos por cima do catálogo base
// sem alterá-lo. Camadas geral ← seguros ← seguros/<tipo>, por chave; o que o
// pacote não traz continua com o texto geral.
import * as Sentry from '@sentry/vue';

const pacoteLoaders = import.meta.glob('./pacotes/**/*.json');

// "seguros.corretora" → ['seguros', 'seguros/corretora'] (da menos para a mais
// específica). Conta sem pacote → [].
export const camadasDoPacote = nome => {
  if (typeof nome !== 'string' || !nome) return [];
  const [segmento, tipo] = nome.split('.');
  if (!segmento) return [];
  return tipo ? [segmento, `${segmento}/${tipo}`] : [segmento];
};

const isObject = valor =>
  valor !== null && typeof valor === 'object' && !Array.isArray(valor);

// Troca só folha de texto que existe no base; chave órfã é ignorada (o CI
// reprova). Devolve o próprio base quando nada muda, e nunca o altera.
const sobrepor = (base, pacote) => {
  if (!isObject(base) || !isObject(pacote)) return base;
  let mudou = false;
  const resultado = { ...base };
  Object.entries(pacote).forEach(([chave, valor]) => {
    const atual = base[chave];
    if (typeof atual === 'string' && typeof valor === 'string') {
      resultado[chave] = valor;
      mudou = true;
    } else if (isObject(atual) && isObject(valor)) {
      const filho = sobrepor(atual, valor);
      if (filho !== atual) {
        resultado[chave] = filho;
        mudou = true;
      }
    }
  });
  return mudou ? resultado : base;
};

export const composeMessages = (base, overlays = []) =>
  overlays.reduce(sobrepor, base);

// Baixa as camadas do idioma. Falha no download não derruba o painel: fica o
// texto geral e o erro vai para o Sentry.
export const carregarPacote = async (locale, camadas) => {
  const loaders = camadas
    .map(camada => pacoteLoaders[`./pacotes/${camada}/${locale}.json`])
    .filter(Boolean);
  if (!loaders.length) return [];
  try {
    const modulos = await Promise.all(loaders.map(load => load()));
    return modulos.map(modulo => modulo.default || modulo);
  } catch (error) {
    Sentry.captureException(error);
    return [];
  }
};
