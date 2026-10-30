import { inject, provide } from 'vue';
import { keysOf, visibleExtras } from '../../customRoles/permissionMatrix';

const CHAVE = Symbol('memoriaDaConversa');

// O que a conversa guiada lembra entre as telas (#2308). Mora no useFuncaoGuiada, não nos componentes: a pergunta é
// desmontada no "Pronto", e a área que muda de lugar em Ajustes é montada de novo.
// - antesDoTudo: a função quando entrou em "Cuida de tudo nas vendas"; sair dele devolve isso (especificação 7.4).
// - por área, o que uma troca de nível mexeu sem a pessoa poder mexer no nível de agora: `tiradas` (a área foi para
//   "Não vê", ou o ajuste é só de quem mexe e foi para "Só olha") e `postas` (ir para "Atende todas" liga os dois
//   alcances, que lá não aparecem). Voltar a um nível que aceita devolve as tiradas e tira as postas, só se continuam
//   como a troca deixou. O que estava à vista no nível do meio fica como a pessoa deixou: o R$ desligado em "Só olha"
//   continua desligado, os relatórios ligados em "Só olha" continuam ligados (revisão do #2308, rodada 3). Esvazia a
//   cada etapa, e numa área a cada troca que não passa por aqui (`esquecer`).
export const criarMemoria = () => {
  let antesDoTudo = null;
  let mexidas = {};

  // `nivelar` aplica o nível escolhido a uma lista de chaves (setLevel ou o equivalente de Vendas).
  const trocarNivel = (module, { permissions, nivelar }) => {
    const daArea = keysOf(module);
    const novas = nivelar(permissions);
    const { tiradas = [], postas = [] } = mexidas[module.key] || {};
    const voltam = tiradas.filter(
      chave =>
        !novas.includes(chave) && nivelar([...novas, chave]).includes(chave)
    );
    const saem = postas.filter(
      chave =>
        novas.includes(chave) &&
        !nivelar(novas.filter(outra => outra !== chave)).includes(chave)
    );
    const final = [...novas.filter(chave => !saem.includes(chave)), ...voltam];
    const escondida = chave =>
      daArea.includes(chave) && !visibleExtras(module, final).includes(chave);
    const tirouAgora = permissions.filter(
      chave =>
        escondida(chave) && !novas.includes(chave) && !postas.includes(chave)
    );
    const pos = novas.filter(
      chave => escondida(chave) && !permissions.includes(chave)
    );
    mexidas = {
      ...mexidas,
      [module.key]: {
        tiradas: [...new Set([...tiradas, ...tirouAgora])].filter(
          chave => !final.includes(chave)
        ),
        postas: [...new Set([...postas, ...pos])].filter(chave =>
          final.includes(chave)
        ),
      },
    };
    return final;
  };

  return {
    antesDoTudo: () => antesDoTudo,
    guardarAntesDoTudo: permissions => {
      antesDoTudo = [...permissions];
    },
    trocarNivel,
    // Uma troca que não passa por trocarNivel (entrar e sair de "Cuida de tudo") vira a página da área: o que estava
    // guardado de antes não volta depois (revisão do #2308, rodada 4).
    esquecer: moduleKey => {
      mexidas = { ...mexidas, [moduleKey]: undefined };
    },
    novaVisita: () => {
      mexidas = {};
    },
    recomecar: () => {
      antesDoTudo = null;
      mexidas = {};
    },
  };
};

export const oferecerMemoria = memoria => provide(CHAVE, memoria);

// Fora da conversa (um componente montado sozinho), cada um lembra só o que é dele.
export const useMemoria = () => inject(CHAVE, null) || criarMemoria();
