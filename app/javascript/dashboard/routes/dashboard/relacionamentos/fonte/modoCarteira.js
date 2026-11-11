// #2897 — o que liga a carteira de seguros no protótipo. Na entrega real quem
// responde é a conta (segmento Seguros + a chave da carteira); aqui, sem chave
// nova, quem responde é a demonstração: a conta fictícia é de seguros em todo
// estado, menos em `?demo=fora-do-segmento`. Sem demonstração, nada de seguro
// aparece nas telas do bloco A.
import {
  DEMO_FORA_DO_SEGMENTO,
  DEMO_SEM_SEGUROS,
  estadoDemo,
} from './modoDemo';

export const contaDeSeguros = () => {
  const estado = estadoDemo();
  return estado !== null && estado !== DEMO_FORA_DO_SEGMENTO;
};

// A aba Seguros pode ser pedida pelo endereço (`?aba=seguros`) em qualquer
// conta que não seja, na demonstração, de outro segmento: sem demonstração a
// fonte real responde (hoje: erro), e a tela mostra o erro dela. Só no ambiente
// de desenvolvimento: em produção o endereço não mostra nada de seguro.
export const abaDeSegurosPermitida = (
  permitida = Boolean(import.meta.env.DEV)
) => permitida && estadoDemo() !== DEMO_FORA_DO_SEGMENTO;

// Na demonstração o Agger já está ligado na conta cheia; em `sem-seguros`
// ainda não (é o ponto de partida das jornadas de trazer).
export const aggerLigadoNaDemo = estado =>
  estado !== null && estado !== DEMO_SEM_SEGUROS && estado !== 'vazio';

// O painel da conversa, na demonstração, mostra os seguros desta pessoa (a
// mesma das jornadas da ficha): a conversa é real e o contato dela não está na
// base inventada.
export const PESSOA_DO_PAINEL_NA_DEMO = 23;

// `?demo-carteira=carregando|erro|vazio` muda só a fonte da carteira: a ficha
// aparece inteira e só a peça de seguros fica no esqueleto, no erro ou vazia.
// Não "gruda": vale para o endereço em que veio.
export const PECAS_DA_CARTEIRA = ['carregando', 'erro', 'vazio'];

export const pecaPedida = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.['demo-carteira'];
  return permitida && PECAS_DA_CARTEIRA.includes(valor) ? valor : null;
};
