// #3099 (F3 do épico #3095) — duas versões da mensagem na campanha e no passo de mensagem da Automação livre.
// Funções puras: a regra padrão, o tamanho do teste e a frase que conta o plano para a pessoa.
//
// Na campanha, uma parte do público recebe o teste (cada versão para um pedaço) e, depois da espera, o resto recebe a
// melhor. O teste tem pelo menos MINIMO_POR_VERSAO pessoas na versão que recebe menos, ou PARTE_DO_TESTE% do público,
// o que for maior. Se o que sobra para o resto é pouco (menos de MINIMO_NO_RESTO), não vale esperar: todo mundo recebe
// uma das duas e o resultado só mostra qual foi melhor (modo "todos").
//
// O servidor faz a mesma conta (o desenho em docs/3099-desenho/desenho.md); a tela só promete o que ele vai fazer.
import { CAMPAIGN_CHANNELS } from './campaignChannels';

export const CRITERIOS = ['respostas', 'compras', 'eu_escolho'];
// Porcentagem do teste que vai para a versão 1; a versão 2 fica com o resto.
export const DIVISOES = [50, 70];
export const ESPERAS = [2, 4, 24];
export const MINIMO_POR_VERSAO = 100;
export const PARTE_DO_TESTE = 20;
export const MINIMO_NO_RESTO = 100;

const ESPERA_POR_CRITERIO = { respostas: 4, compras: 24, eu_escolho: 4 };

export const esperaPadrao = criterio => ESPERA_POR_CRITERIO[criterio] ?? 4;

export const regraPadrao = () => ({
  criterio: 'respostas',
  divisao: 50,
  espera: esperaPadrao('respostas'),
});

// O rascunho das duas versões guardado no rascunho da campanha (`draft.duasVersoes`).
export const duasVersoesVazias = () => ({
  ligado: false,
  texto: '',
  templateId: null,
  assunto: '',
  ...regraPadrao(),
});

// Trocar o critério leva a espera para o padrão dele, a não ser que a pessoa já tenha mudado a espera à mão.
export const trocarCriterio = (regra, criterio) => {
  const esperaFoiMexida = regra.espera !== esperaPadrao(regra.criterio);
  return {
    ...regra,
    criterio,
    espera: esperaFoiMexida ? regra.espera : esperaPadrao(criterio),
  };
};

const dividir = (total, divisao) => {
  const versao1 = Math.round((total * divisao) / 100);
  return { versao1, versao2: total - versao1 };
};

// `publico`: quantas pessoas vão receber (já sem o grupo de controle da F2).
export const planoDoTeste = (publico, { divisao = 50 } = {}) => {
  const total = Math.max(0, Math.floor(Number(publico) || 0));
  const menorParte = (100 - Math.max(divisao, 100 - divisao)) / 100;
  const minimoDoTeste = Math.ceil(MINIMO_POR_VERSAO / menorParte);
  const teste = Math.max(
    minimoDoTeste,
    Math.ceil((total * PARTE_DO_TESTE) / 100)
  );
  if (total - teste < MINIMO_NO_RESTO) {
    return {
      modo: 'todos',
      teste: total,
      ...dividir(total, divisao),
      resto: 0,
      pequeno: total < minimoDoTeste,
      minimo: minimoDoTeste,
    };
  }
  return {
    modo: 'teste',
    teste,
    ...dividir(teste, divisao),
    resto: total - teste,
    pequeno: false,
    minimo: minimoDoTeste,
  };
};

const DEPOIS = {
  respostas: 'DEPOIS_RESPOSTAS',
  compras: 'DEPOIS_COMPRAS',
  eu_escolho: 'DEPOIS_EU_ESCOLHO',
};

// As frases do plano, na ordem, como { chave, params } (os números ainda sem formatar). A tela traduz.
export const frasesDoPlano = (plano, regra) => {
  if (plano.modo === 'todos') {
    const frases = [
      {
        chave: 'TODOS',
        params: { total: plano.teste, v1: plano.versao1, v2: plano.versao2 },
      },
    ];
    if (plano.pequeno)
      frases.push({ chave: 'PEQUENO', params: { minimo: plano.minimo } });
    return frases;
  }
  const frases = [
    {
      chave: 'TESTE',
      params: { teste: plano.teste, v1: plano.versao1, v2: plano.versao2 },
    },
    {
      chave: DEPOIS[regra.criterio] || DEPOIS.respostas,
      params: { horas: regra.espera, resto: plano.resto },
    },
  ];
  if (regra.criterio !== 'eu_escolho')
    frases.push({ chave: 'EMPATE', params: {} });
  return frases;
};

// Na automação não há "resto" contado: cada pessoa que passa recebe uma das duas até o teste fechar.
export const frasesDaAutomacao = regra => {
  const depois = {
    respostas: 'AUTOMACAO_DEPOIS_RESPOSTAS',
    compras: 'AUTOMACAO_DEPOIS_COMPRAS',
    eu_escolho: 'AUTOMACAO_DEPOIS_EU_ESCOLHO',
  };
  const frases = [
    {
      chave: regra.divisao === 50 ? 'AUTOMACAO_METADE' : 'AUTOMACAO_MAIS_NA_1',
      params: {},
    },
    {
      chave: depois[regra.criterio] || depois.respostas,
      params: { minimo: MINIMO_POR_VERSAO, horas: regra.espera },
    },
  ];
  if (regra.criterio !== 'eu_escolho')
    frases.push({ chave: 'EMPATE', params: {} });
  return frases;
};

const limpo = valor => String(valor ?? '').trim();

// A versão 2 está pronta para seguir: escrita e diferente da versão 1. `primeira`: { texto, templateId, assunto }.
// Comparação de igualdade exata (depois de tirar espaços das pontas), não interpretação do texto.
export const motivoDaSegunda = (canal, versoes, primeira = {}) => {
  if (!versoes?.ligado) return null;
  const campo = {
    [CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL]: 'templateId',
    [CAMPAIGN_CHANNELS.EMAIL]: 'assunto',
  }[canal];
  const chave = campo || 'texto';
  const segunda = limpo(versoes[chave]);
  if (!segunda) return 'VAZIA';
  if (segunda === limpo(primeira[chave])) return 'IGUAL';
  return null;
};

export const segundaVersaoPronta = (canal, versoes, primeira) =>
  motivoDaSegunda(canal, versoes, primeira) === null;
