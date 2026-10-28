import { inject, provide } from 'vue';

const CHAVE = Symbol('memoriaDaConversa');

// O que a conversa guiada lembra entre as telas (#2308). Mora no useFuncaoGuiada, não nos componentes: a pergunta é
// desmontada no "Pronto", e a área que muda de lugar em Ajustes é montada de novo.
// - antesDoTudo: a função quando entrou em "Cuida de tudo nas vendas"; sair dele devolve isso (decisão 5).
// - entrouCom: o que entrou junto com uma chave (as metas trazem o R$); desligar a chave tira só isso (decisão 6).
// - niveis: por área, as chaves dela em cada nível por onde a pessoa passou nesta visita à tela. Voltar a um nível
//   devolve os ajustes de lá, e passar por "Não vê" com as setas não apaga nada (decisão 5). Esvazia a cada etapa.
// As chaves de uma área, como o permissionMatrix as conta (níveis e ajustes).
const chavesDaArea = module => [
  ...Object.values(module.levels || {}),
  ...(module.extras || []),
];

export const criarMemoria = () => {
  let antesDoTudo = null;
  let entrouCom = {};
  let niveis = {};

  // `novas` é o que o nível escolhido grava sozinho; volta com os ajustes de lá, se a pessoa já passou por ele.
  const trocarNivel = (module, { de, para, permissions, novas }) => {
    const daArea = chavesDaArea(module);
    const lembrados = {
      ...(niveis[module.key] || {}),
      [de]: permissions.filter(chave => daArea.includes(chave)),
    };
    niveis = { ...niveis, [module.key]: lembrados };
    const guardadas = lembrados[para];
    if (!guardadas) return novas;
    return [...novas.filter(chave => !daArea.includes(chave)), ...guardadas];
  };

  return {
    antesDoTudo: () => antesDoTudo,
    guardarAntesDoTudo: permissions => {
      antesDoTudo = [...permissions];
    },
    entrouCom: chave => entrouCom[chave] || [],
    guardarEntrouCom: (chave, chaves) => {
      entrouCom = { ...entrouCom, [chave]: [...chaves] };
    },
    trocarNivel,
    novaVisita: () => {
      niveis = {};
    },
    recomecar: () => {
      antesDoTudo = null;
      entrouCom = {};
      niveis = {};
    },
  };
};

export const oferecerMemoria = memoria => provide(CHAVE, memoria);

// Fora da conversa (um componente montado sozinho), cada um lembra só o que é dele.
export const useMemoria = () => inject(CHAVE, null) || criarMemoria();
