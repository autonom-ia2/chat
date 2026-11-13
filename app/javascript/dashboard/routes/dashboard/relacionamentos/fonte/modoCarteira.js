// #2897 — o que liga a carteira de seguros nas telas de Relacionamentos: a aba
// Seguros e o bloco Seguros das fichas. Quem responde é a conta: o payload dela
// traz `carteira_seguros` (chave ligada e corretora de seguros; o servidor
// decide em Carteira::Acesso). Sem isso nada de seguro aparece e nenhuma rota
// da carteira é chamada.
//
// Na demonstração (`?demo=`, só em desenvolvimento) a conta fictícia é de
// seguros em todo estado, menos em `?demo=fora-do-segmento`.
import { DEMO_FORA_DO_SEGMENTO } from './modoDemo';

// `demo`: o estado da demonstração (ou nulo, fora dela). `conta`: a conta que
// está aberta, como o servidor mandou.
export const contaDeSeguros = (demo, conta) =>
  demo ? demo !== DEMO_FORA_DO_SEGMENTO : conta?.carteira_seguros === true;

// `?demo-carteira=carregando|erro|vazio` muda só a fonte da carteira: a ficha
// aparece inteira e só a peça de seguros fica no esqueleto, no erro ou vazia.
// Não "gruda": vale para o endereço em que veio, e só no desenvolvimento.
export const PECAS_DA_CARTEIRA = ['carregando', 'erro', 'vazio'];

export const pecaPedida = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.['demo-carteira'];
  return permitida && PECAS_DA_CARTEIRA.includes(valor) ? valor : null;
};
