import { holdsKey } from 'dashboard/helper/peopleAccess';
import contrato from './semFuncaoCapacidades.json';
import { comImplicadas } from './comImplicadas';

// O que muda para quem fica sem função (#2308, especificação 5.D, 5.E e 7.9). Lê o contrato gerado das policies
// (semFuncaoCapacidades.json, PR 2) e nunca uma lista escrita à mão por função. Devolve ids do contrato; o texto de
// cada um fica em FUNCOES_EQUIPE.SEM_FUNCAO.<id>. `estaLigada(flag)` diz se uma flag da conta está ligada: os
// relatórios das vendas dependem de crm_numeros_lentes.
const podeSemFuncao = (capacidade, estaLigada) => {
  const flag = capacidade.depende_da_flag;
  if (!flag) return capacidade.pode;
  return estaLigada(flag.flag) ? flag.ligada : flag.desligada;
};

export const capacidadesSemFuncao = estaLigada =>
  contrato.capacidades.map(capacidade => ({
    id: capacidade.id,
    pode: podeSemFuncao(capacidade, estaLigada),
  }));

// A função tem uma capacidade que o "Sem função" dá quando tem todas as chaves dela (quem só olha os contatos ganha
// mudar os contatos); tem uma que ele não dá quando tem qualquer uma (quem só vê as buscas perde procurar clientes).
// `_manage` vale como `_view`, como no servidor.
const temChave = permissions => chave => holdsKey({ permissions }, chave);

const CHAVES = new Map(
  contrato.capacidades.map(capacidade => [capacidade.id, capacidade.chaves])
);

export const diffEntre = (permissions, estaLigada) => {
  const tem = temChave(comImplicadas(permissions));
  const capacidades = capacidadesSemFuncao(estaLigada);
  return {
    ganha: capacidades
      .filter(({ id, pode }) => pode && !CHAVES.get(id).every(tem))
      .map(({ id }) => id),
    perde: capacidades
      .filter(({ id, pode }) => !pode && CHAVES.get(id).some(tem))
      .map(({ id }) => id),
  };
};
