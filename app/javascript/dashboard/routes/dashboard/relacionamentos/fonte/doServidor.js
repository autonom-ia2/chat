import { SEM_ACESSO } from '../lista/falhas';

// #2896 — a ida ao servidor que as fontes de Relacionamentos dividem (a lista e
// "Trazer minha lista"). O servidor responde 401 quando a permissão recusa (e
// sem sessão) e, na lista, 403 quando Empresas está desligada na conta ("Trazer
// minha lista" nunca responde 403): nos dois a pessoa não pode ver, e tentar de
// novo não resolve.
const STATUS_SEM_ACESSO = [401, 403];

const erroSemAcesso = causa =>
  Object.assign(new Error('Sem acesso a Relacionamentos.', { cause: causa }), {
    name: SEM_ACESSO,
  });

// `pedido` é a promessa de uma ida ao servidor: devolve o corpo da resposta. A
// recusa por falta de acesso ganha nome; qualquer outro erro sobe como veio.
export const doServidor = async pedido => {
  try {
    return (await pedido).data;
  } catch (falha) {
    throw STATUS_SEM_ACESSO.includes(falha?.response?.status)
      ? erroSemAcesso(falha)
      : falha;
  }
};
