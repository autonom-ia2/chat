// Para a lista de mensagens com pele (#1702): qual balão abre uma sequência (leva o
// bico, o nome de quem mandou e o respiro acima) e onde o dia muda (leva a etiqueta do
// dia). Sem pele, nada muda na lista. Com pele, esta é a única regra de sequência: o
// `group-with-next` do Chatwoot (por minuto) só esconde o avatar, que a pele já esconde.
import { computed } from 'vue';
import { fornecerPrimeiras, useFuso, usePele } from './pele';
import { diaDaMensagem } from './dataDaConversa';
import { MESSAGE_TYPES } from '../message/constants';
import { ehEcoDoCelular, idDoAutorDoEco } from './ecoDoCelular';
import { origemDaMensagem } from './origemDoEnvio';

// De que lado o balão fica: cliente, empresa, nota da equipe ou aviso do sistema.
const ladoDoBalao = mensagem => {
  if (mensagem.private) return 'nota';
  if (mensagem.messageType === MESSAGE_TYPES.INCOMING) return 'cliente';
  if (
    [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE].includes(
      mensagem.messageType
    )
  ) {
    return 'empresa';
  }
  return 'aviso';
};

// Tipo e id: atendente 1 e robô 1 são pessoas diferentes. O eco do celular (#1941) é de
// quem estava atribuído quando chegou, não do remetente (no WAHA, o dono da chave).
const quemMandou = mensagem => {
  if (ehEcoDoCelular(mensagem.contentAttributes)) {
    return `eco:${idDoAutorDoEco(mensagem.contentAttributes) ?? ''}`;
  }
  // #2048: envio automático em nome da pessoa leva o nome da origem, então a origem abre
  // sequência própria; senão o follow-up logo depois da resposta dela ficaria sem nome.
  const tipo = mensagem.sender?.type ?? mensagem.senderType ?? '';
  const origem = origemDaMensagem(tipo, mensagem.contentAttributes);
  if (origem) return `origem:${origem}`;
  return `${tipo}:${mensagem.senderId ?? mensagem.sender?.id}`;
};

// Como no app: a sequência segue enquanto a mesma pessoa fala no mesmo dia, sem
// quebrar a cada minuto. Do lado da empresa, troca de atendente abre sequência nova
// (o nome aparece no topo do balão). Mensagem que falhou abre sequência.
export const continuaASequencia = (anterior, atual, fuso) => {
  const lado = ladoDoBalao(atual);
  if (lado === 'aviso' || lado !== ladoDoBalao(anterior)) return false;
  if (atual.status === 'failed' || anterior.status === 'failed') return false;
  if (quemMandou(atual) !== quemMandou(anterior)) return false;
  return (
    diaDaMensagem(atual.createdAt, fuso) ===
    diaDaMensagem(anterior.createdAt, fuso)
  );
};

export const useSequenciaDaConversa = mensagens => {
  const pele = usePele();
  const fuso = useFuso();

  const primeiras = computed(() => {
    if (!pele.value) return new Set();
    const lista = mensagens.value;
    return new Set(
      lista
        .filter(
          (mensagem, i) =>
            i === 0 || !continuaASequencia(lista[i - 1], mensagem, fuso.value)
        )
        .map(mensagem => mensagem.id)
    );
  });
  fornecerPrimeiras(primeiras);

  // Calculado uma vez por mudança na lista (não a cada balão desenhado).
  const quemAbreODia = computed(() => {
    if (!pele.value) return new Set();
    const lista = mensagens.value;
    const dias = lista.map(mensagem =>
      diaDaMensagem(mensagem.createdAt, fuso.value)
    );
    return new Set(
      lista
        .filter((_, i) => i === 0 || dias[i] !== dias[i - 1])
        .map(mensagem => mensagem.id)
    );
  });
  const abreODia = index => quemAbreODia.value.has(mensagens.value[index]?.id);

  return { abreODia, pele };
};
