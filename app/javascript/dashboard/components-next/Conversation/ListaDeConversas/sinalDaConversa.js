// #2202 — a linha 3 da lista: o que pede atenção, um sinal só. A regra é igual em
// todas as abas: vale a primeira condição verdadeira.
//   R  Resolvida (só no resultado da busca, #2211: lá aparece conversa resolvida)
//   0  Sua vez (convite para mim)        0b Reservada (convite para outra pessoa)
//   1  Adiada (só aparece na lista de adiadas, que só tem adiadas)
//   2  O robô pediu ajuda               3  O cliente espera
//   4  Quem cuida: "Ana respondeu sem pegar" em todas as abas; "Com Ana",
//      "Com Gabriela [IA]" e "Sem ninguém" só onde a aba não diz isso (mostrarResponsavel).
// A prioridade vem antes do sinal, só quando é urgente ou alta.
// Sem regex e sem ler o texto das mensagens: tudo sai dos campos da conversa.
import { FAIXA, duracaoDaEspera, faixaDaEspera } from './duracaoDaEspera';
import { horaComDia } from './horaDaLista';
import {
  REMETENTE,
  ehRespostaDePessoa,
  ehTipoDeRobo,
  primeiroNome,
} from './prefixoDoRemetente';

export const FAIXA_DA_VEZ = 'vez';
export const FAIXA_NEUTRA = 'neutra';

const MINUTO = 60;
const PRIORIDADES = { urgent: 'URGENTE', high: 'ALTA' };
const ESPERA_DO_CLIENTE = [REMETENTE.CLIENTE, REMETENTE.NOTA];

const segundosDe = valor => {
  if (!valor) return 0;
  if (typeof valor === 'number') return valor;
  const ms = Date.parse(valor);
  return Number.isNaN(ms) ? 0 : Math.floor(ms / 1000);
};

const responsavel = chat => ({
  tipo: chat.meta?.assignee_type,
  pessoa: chat.meta?.assignee || null,
});

const temPessoaResponsavel = chat => {
  const { tipo, pessoa } = responsavel(chat);
  return Boolean(pessoa?.id) && !ehTipoDeRobo(tipo);
};

const nomeDoRobo = (chat, contexto) => {
  const { tipo, pessoa } = responsavel(chat);
  if (ehTipoDeRobo(tipo) && pessoa?.name) return pessoa.name;
  return contexto.nomeDoUltimoRobo || '';
};

const sinal = (familia, texto, faixa, extras = {}) => ({
  familia,
  texto,
  faixa,
  aria: extras.aria || texto,
  icone: extras.icone || '',
  selo: Boolean(extras.selo),
  nome: extras.nome || '',
});

const convite = (chat, contexto) => {
  const entrega = chat.additional_attributes?.crm_entrega;
  if (entrega?.modo !== 'convite') return null;
  const ate = segundosDe(entrega.ate);
  const restante = ate - contexto.agora;
  if (!ate || restante <= 0) return null;
  const { t } = contexto;
  const minutos = Math.floor(restante / MINUTO);
  if (Number(entrega.convidado_id) === Number(contexto.euId)) {
    const texto =
      minutos < 1
        ? t('LISTA_DE_CONVERSAS.SINAL.SUA_VEZ_AGORA')
        : t('LISTA_DE_CONVERSAS.SINAL.SUA_VEZ', { n: minutos });
    const aria = t('LISTA_DE_CONVERSAS.ARIA.SUA_VEZ', {
      n: Math.max(minutos, 1),
    });
    return sinal('vez', texto, FAIXA_DA_VEZ, { aria, icone: 'i-lucide-clock' });
  }
  const nome = primeiroNome(contexto.nomeDoAgente(entrega.convidado_id));
  const texto = nome
    ? t('LISTA_DE_CONVERSAS.SINAL.RESERVADA', { nome })
    : t('LISTA_DE_CONVERSAS.SINAL.RESERVADA_SEM_NOME');
  const aria = t('LISTA_DE_CONVERSAS.ARIA.RESERVADA', {
    nome: nome || t('LISTA_DE_CONVERSAS.SINAL.OUTRA_PESSOA'),
    n: Math.max(minutos, 1),
  });
  return sinal('reservada', texto, FAIXA_NEUTRA, {
    aria,
    icone: 'i-lucide-user-round',
  });
};

const resolvida = (chat, contexto) => {
  if (!contexto.marcarResolvida || chat.status !== 'resolved') return null;
  return sinal(
    'resolvida',
    contexto.t('LISTA_DE_CONVERSAS.SINAL.RESOLVIDA'),
    FAIXA_NEUTRA,
    { icone: 'i-lucide-circle-check' }
  );
};

const adiada = (chat, contexto) => {
  if (chat.status !== 'snoozed') return null;
  const { t } = contexto;
  const ate = segundosDe(chat.snoozed_until);
  const texto = ate
    ? t('LISTA_DE_CONVERSAS.SINAL.ADIADA_ATE', {
        quando: horaComDia({ ...contexto, quando: ate }),
      })
    : t('LISTA_DE_CONVERSAS.SINAL.ADIADA_CLIENTE');
  return sinal('adiada', texto, FAIXA_NEUTRA, {
    icone: 'i-lucide-alarm-clock',
  });
};

// Com 7 dias ou mais, a cor sai e a frase troca junto (decisão 6).
const faixaComParada = segundos => faixaDaEspera(segundos);

const pediuAjuda = (chat, contexto) => {
  const desde = segundosDe(
    chat.additional_attributes?.bot_handoff_waiting_since
  );
  if (!desde || !(chat.waiting_since > 0)) return null;
  const { t } = contexto;
  const espera = contexto.agora - desde;
  const nome = nomeDoRobo(chat, contexto);
  const duracao = duracaoDaEspera(espera, t);
  const texto = nome
    ? t('LISTA_DE_CONVERSAS.SINAL.PEDIU_AJUDA', { nome, duracao })
    : t('LISTA_DE_CONVERSAS.SINAL.ASSISTENTE_PEDIU_AJUDA', { duracao });
  const aria = t('LISTA_DE_CONVERSAS.ARIA.PEDIU_AJUDA', {
    nome: nome || t('LISTA_DE_CONVERSAS.SINAL.ASSISTENTE'),
    duracao,
  });
  return sinal('ajuda', texto, faixaComParada(espera), {
    aria,
    icone: 'i-lucide-hand',
    selo: !nome,
    nome,
  });
};

const esperando = (chat, contexto) => {
  if (!(chat.waiting_since > 0)) return null;
  if (!ESPERA_DO_CLIENTE.includes(contexto.ultima?.tipo)) return null;
  const { t } = contexto;
  const espera = contexto.agora - chat.waiting_since;
  const faixa = faixaComParada(espera);
  const duracao = duracaoDaEspera(espera, t);
  const chave = faixa === FAIXA.PARADA ? 'SEM_RESPOSTA' : 'ESPERANDO';
  return sinal(
    'espera',
    t(`LISTA_DE_CONVERSAS.SINAL.${chave}`, { duracao }),
    faixa
  );
};

const quemCuida = (chat, contexto) => {
  const { t, ultima, mostrarResponsavel } = contexto;
  if (!temPessoaResponsavel(chat) && ehRespostaDePessoa(ultima)) {
    const texto =
      ultima.tipo === REMETENTE.VOCE
        ? t('LISTA_DE_CONVERSAS.SINAL.VOCE_RESPONDEU')
        : t('LISTA_DE_CONVERSAS.SINAL.RESPONDEU_SEM_PEGAR', {
            nome: ultima.nome,
          });
    return sinal('respondeu', texto, FAIXA_NEUTRA);
  }
  if (!mostrarResponsavel) return null;
  const { tipo, pessoa } = responsavel(chat);
  if (pessoa?.id && ehTipoDeRobo(tipo)) {
    const nome = pessoa.name;
    return sinal(
      'com_robo',
      t('LISTA_DE_CONVERSAS.SINAL.COM', { nome }),
      FAIXA_NEUTRA,
      {
        aria: t('LISTA_DE_CONVERSAS.ARIA.COM_ROBO', { nome }),
        selo: true,
        nome,
      }
    );
  }
  if (pessoa?.id) {
    const nome = primeiroNome(pessoa.available_name || pessoa.name);
    return sinal(
      'com',
      t('LISTA_DE_CONVERSAS.SINAL.COM', { nome }),
      FAIXA_NEUTRA
    );
  }
  return sinal(
    'ninguem',
    t('LISTA_DE_CONVERSAS.SINAL.SEM_NINGUEM'),
    FAIXA_NEUTRA
  );
};

const REGRAS = [resolvida, convite, adiada, pediuAjuda, esperando, quemCuida];

// contexto: { t, agora, fuso, euId, ultima (prefixoDoRemetente), nomeDoUltimoRobo,
//             nomeDoAgente(id), mostrarResponsavel, marcarResolvida }
export const sinalDaConversa = (chat, contexto) => {
  const chave = PRIORIDADES[chat.priority];
  const prioridade = chave
    ? contexto.t(`LISTA_DE_CONVERSAS.PRIORIDADE.${chave}`)
    : '';
  const encontrado = REGRAS.reduce(
    (achado, regra) => achado || regra(chat, contexto),
    null
  );
  return { prioridade, sinal: encontrado };
};
