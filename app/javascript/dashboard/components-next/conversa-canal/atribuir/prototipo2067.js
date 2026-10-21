// PROTÓTIPO #2067 (só para o Rodrigo comparar; sai na implementação).
//
// 1) Qual das três formas da opção "ficar com a conversa" aparece: ?atribuir=a|b|c
//    a = chip ao lado do Enviar · b = linha de status acima da barra · c = Enviar dividido.
// 2) Onde fica o "Devolver para a IA": ?devolver=topo|barra (topo = cabeçalho, a escolha).
// A escolha fica guardada neste navegador, para valer ao trocar de conversa pela lista.
const FORMAS = ['a', 'b', 'c'];
const LUGARES = ['topo', 'barra'];
const CHAVE = 'prototipo2067';

const lerGuardado = () => {
  try {
    return JSON.parse(window.localStorage.getItem(CHAVE)) || {};
  } catch {
    return {};
  }
};

const guardar = valor => {
  try {
    window.localStorage.setItem(CHAVE, JSON.stringify(valor));
  } catch {
    // Sem armazenamento (janela anônima): vale só o endereço.
  }
};

export const escolhaDoPrototipo = query => {
  const guardado = lerGuardado();
  const forma = FORMAS.includes(query?.atribuir)
    ? query.atribuir
    : guardado.forma;
  const lugar = LUGARES.includes(query?.devolver)
    ? query.devolver
    : guardado.lugar;
  const escolha = {
    forma: FORMAS.includes(forma) ? forma : 'a',
    lugar: LUGARES.includes(lugar) ? lugar : 'barra',
  };
  guardar(escolha);
  return escolha;
};

// ADAPTADOR: o painel ainda não recebe "de qual agente de IA a conversa veio". Na
// implementação, isso sai do registro de passagens do CRM (crm_passagens: de um agente
// de IA para a pessoa que está com a conversa) e chega junto com a conversa. Na demo,
// o banco local grava o agente em additional_attributes.prototipo_2067_veio_da_ia.
export const iaDeOrigem = conversa => {
  const ia = conversa?.additional_attributes?.prototipo_2067_veio_da_ia;
  return ia?.id ? { id: ia.id, nome: ia.name } : null;
};
