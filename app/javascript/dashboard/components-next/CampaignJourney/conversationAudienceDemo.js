// Demo adapter of "Novo público pedindo em palavras" (#2277, prototype). It answers the same calls the real
// endpoint will (status → plan → start → progress → result) with fictitious data, so the screen can be
// approved in the real panel before the backend exists. Swapped by the API client once the backend lands.
// `?demo=` on the page picks a branch: `sem-chave` (account without its own AI key), `fila` (another search
// of the account is running), `vazio` (nobody found), `sem-conversas` (short periods without conversations),
// `erro` (the account's AI stops answering midway) and `teto` (the agreed cost is reached; it asks first).

const USD_BRL = 5.42;
const TOTAL_CONVERSATIONS = 1412;
const TICK_MS = 600;
const PER_TICK = 141;

// [name, phone, group, why the person came in, what the person wrote: [date, message] for each time it counts].
// "Com certeza" always proves the chosen rule (2 times or more); "Provável" has a doubt about the rule itself;
// "Ficaram de fora" asked once, or did not really ask.
const PEOPLE = [
  [
    'Mariana Lopes',
    '+55 11 9•••• 4821',
    'certeza',
    'Pediu cotação 3 vezes: 12/09, 30/09 e 14/10',
    [
      ['12/09', 'Oi! Quanto fica para 2 pessoas em dezembro?'],
      ['30/09', 'Pode refazer a cotação com outra data?'],
      ['14/10', 'Queria cotar de novo, agora para 3 pessoas.'],
    ],
  ],
  [
    'Ricardo Almeida',
    '+55 21 9•••• 1177',
    'certeza',
    'Pediu cotação 2 vezes: 05/10 e 19/10',
    [
      ['05/10', 'Me manda uma cotação para a viagem de janeiro?'],
      [
        '19/10',
        'Refaz a cotação? Vocês fazem um preço melhor se eu fechar hoje?',
      ],
    ],
  ],
  [
    'Beatriz Nogueira',
    '+55 11 9•••• 6630',
    'certeza',
    'Pediu cotação 2 vezes: 02/09 e 25/09',
    [
      ['02/09', 'Quero uma cotação para 30 dias fora.'],
      ['25/09', 'Mudou a data. Pode cotar de novo?'],
    ],
  ],
  [
    'Carlos Eduardo Pinto',
    '+55 31 9•••• 2045',
    'certeza',
    'Pediu cotação 2 vezes: 22/09 e 08/10',
    [
      ['22/09', 'Preciso de uma cotação para levar na escola.'],
      ['08/10', 'A escola pediu outra cotação, com mais cobertura.'],
    ],
  ],
  [
    'Fernanda Ribeiro',
    '+55 41 9•••• 7712',
    'certeza',
    'Pediu cotação 2 vezes: 18/09 e 18/10',
    [
      ['18/09', 'Somos 2 adultos e 2 crianças. Quanto fica?'],
      ['18/10', 'Pode cotar de novo para a família?'],
    ],
  ],
  [
    'Thiago Moreira',
    '+55 11 9•••• 5590',
    'certeza',
    'Pediu cotação 2 vezes: 03/10 e 21/10',
    [
      ['03/10', 'Me passa uma cotação?'],
      ['21/10', 'Consegue me mandar aquela cotação de novo?'],
    ],
  ],
  [
    'João Victor Sales',
    '+55 11 9•••• 3398',
    'provavel',
    'Pediu 2 vezes, mas uma pode ter sido para outra pessoa',
    [
      ['10/09', 'Quanto custa para mim em novembro?'],
      ['01/10', 'E para a minha irmã, quanto fica?'],
    ],
  ],
  [
    'Patrícia Moura',
    '+55 19 9•••• 5521',
    'provavel',
    'Pediu 2 vezes; na segunda não deu para saber se era viagem',
    [
      ['15/09', 'Me passa os valores da viagem que eu te mando as datas.'],
      ['12/10', 'Me manda aquela cotação de novo?'],
    ],
  ],
  [
    'André Carvalho',
    '+55 11 9•••• 8807',
    'provavel',
    'Pediu 2 vezes: na 2ª, só perguntou se o preço ainda valia',
    [
      ['20/09', 'Quero uma cotação para o cruzeiro.'],
      ['09/10', 'Aquele preço ainda vale?'],
    ],
  ],
  [
    'Camila Duarte',
    '+55 48 9•••• 3312',
    'fora',
    'Pediu cotação só 1 vez (02/10)',
    [['02/10', 'Me manda uma cotação? Vou ver com meu marido.']],
  ],
  [
    'Larissa Campos',
    '+55 61 9•••• 2290',
    'fora',
    'Pediu cotação só 1 vez, para o filho',
    [['28/09', 'É para o meu filho, ele viaja mês que vem.']],
  ],
  [
    'Luciana Prado',
    '+55 51 9•••• 6614',
    'fora',
    'Disse que talvez viaje, sem pedir cotação',
    [['11/10', 'Talvez eu viaje no fim do ano, depois falo com vocês.']],
  ],
  [
    'Vanessa Rocha',
    '+55 11 9•••• 1430',
    'fora',
    'Perguntou se vocês atendem, sem pedir cotação',
    [['16/10', 'Vocês atendem fim de semana?']],
  ],
];

// People who match but cannot receive: no WhatsApp, or asked not to receive. They never count.
const LEFT_ASIDE = [
  ['Rogério Lima', 'sem_whatsapp'],
  ['Sandra Vieira', 'sem_whatsapp'],
  ['Paulo Henrique Dias', 'nao_quer'],
];

const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const brl = usd => Math.round(usd * USD_BRL * 100) / 100;
const cost = usd => ({ usd, brl: brl(usd) });

const person = ([name, phone, confidence, reason, asks], index) => ({
  id: index + 1,
  name,
  phone,
  confidence,
  reason,
  asks,
  conversationId: 1200 + index * 7,
});

const PLANS = {
  '7d': { conversations: 64, usd: 0.03, minutes: 1 },
  '30d': { conversations: 286, usd: 0.11, minutes: 1 },
  '3m': { conversations: 702, usd: 0.25, minutes: 2 },
  '12m': { conversations: TOTAL_CONVERSATIONS, usd: 0.48, minutes: 4 },
  all: { conversations: 1906, usd: 0.64, minutes: 5 },
};

const PERIOD_WORDS = {
  '7d': 'nos últimos 7 dias',
  '30d': 'nos últimos 30 dias',
  '3m': 'nos últimos 3 meses',
  '12m': 'no último ano',
  all: 'em todas as conversas',
};

// `teto`: the conversations are longer than estimated, so the price per conversation is 3.4× the estimate and
// the agreed ceiling (twice the estimate) is reached before the end. `erro`: the AI stops answering at 40%.
const TETO_SPEND = 3.4;
const ERROR_AT = 0.4;

export const createConversationAudienceDemo = ({ mode = '' } = {}) => {
  let read = 0;
  let timer = null;
  let interrupted = false;

  const found = mode === 'vazio' ? [] : PEOPLE.map(person);
  const spend = mode === 'teto' ? TETO_SPEND : 1;
  const spentUsd = (plan, share) =>
    Math.round(plan.cost.usd * share * spend * 100) / 100;

  const snapshot = (state, total, plan, usd) => {
    const share = total ? read / total : 0;
    const done = state === 'pronto';
    return {
      state,
      read,
      total,
      people: done ? found : found.slice(0, Math.floor(share * PEOPLE.length)),
      cost: cost(usd ?? spentUsd(plan, share)),
      leftAside: done && found.length ? LEFT_ASIDE : [],
    };
  };

  // Where this tick stops on its own, if it does: the agreed cost, or the AI that stopped answering.
  const interruption = (plan, total) => {
    if (interrupted) return null;
    const share = read / total;
    if (mode === 'teto' && spentUsd(plan, share) >= plan.ceiling.usd) {
      return snapshot('teto', total, plan, plan.ceiling.usd);
    }
    if (mode === 'erro' && share >= ERROR_AT)
      return snapshot('erro', total, plan);
    return null;
  };

  return {
    // Whether the account has its own AI key connected (the search never uses the installation key) and how
    // many conversations each period has, so an empty period cannot be picked.
    async status() {
      await wait(150);
      const periods = Object.fromEntries(
        Object.entries(PLANS).map(([key, value]) => [key, value.conversations])
      );
      if (mode === 'sem-conversas') {
        periods['7d'] = 0;
        periods['30d'] = 0;
      }
      return { hasOwnKey: mode !== 'sem-chave', periods };
    },

    // The manager model turns the request into a plan; an ambiguous request comes back with one question.
    // The demo always asks once, so the question screen can be seen; the real model decides by itself.
    async plan({ period, answer }) {
      await wait(900);
      if (!answer) {
        return {
          question: {
            text: 'Quem você quer na lista?',
            options: [
              { id: 'todos', label: 'Todo mundo que pediu cotação' },
              {
                id: 'repetidos',
                label: 'Só quem pediu cotação 2 vezes ou mais',
              },
            ],
          },
        };
      }
      const base = PLANS[period] || PLANS['12m'];
      const who =
        answer === 'repetidos'
          ? 'Pessoas que pediram cotação de viagem 2 vezes ou mais'
          : 'Pessoas que pediram cotação de viagem, quem pediu mais vezes primeiro';
      return {
        understood: `${who}, ${PERIOD_WORDS[period] || PERIOD_WORDS['12m']}.`,
        name:
          answer === 'repetidos'
            ? 'Pediram cotação 2 vezes ou mais'
            : 'Pediram cotação',
        conversations: base.conversations,
        cost: cost(base.usd),
        ceiling: cost(base.usd * 2),
        minutes: base.minutes,
      };
    },

    async start() {
      await wait(300);
      read = 0;
      interrupted = false;
      return { queued: mode === 'fila', aheadMinutes: mode === 'fila' ? 2 : 0 };
    },

    // Progress while the readers go through the conversations; people appear as they are found.
    watch(plan, onChange) {
      const total = plan.conversations;
      let queuedTicks = mode === 'fila' ? 5 : 0;
      clearInterval(timer);
      timer = setInterval(() => {
        if (queuedTicks > 0) {
          queuedTicks -= 1;
          onChange({ ...snapshot('fila', total, plan), aheadMinutes: 2 });
          return;
        }
        read = Math.min(total, read + PER_TICK);
        const stopped = interruption(plan, total);
        if (stopped) {
          clearInterval(timer);
          onChange(stopped);
          return;
        }
        const done = read >= total;
        onChange(snapshot(done ? 'pronto' : 'lendo', total, plan));
        if (done) clearInterval(timer);
      }, TICK_MS);
    },

    // "Continuar" after the agreed cost or after the AI is back: goes on from where it stopped.
    resume(plan, onChange) {
      interrupted = true;
      this.watch(plan, onChange);
    },

    // Stops the readers; who was found so far stays.
    stop() {
      clearInterval(timer);
    },

    // Leaving the screen: the real search keeps running on the server; the demo only stops its clock.
    detach() {
      clearInterval(timer);
    },

    // The conversation beside the list: each message that counts, with its date and marked as the reason, and
    // the team's answer after it.
    async conversation(id) {
      await wait(250);
      const match = found.find(item => item.conversationId === id);
      return (match?.asks || []).flatMap(([date, text]) => [
        { from: 'contato', date, text, counts: true },
        { from: 'equipe', date, text: 'Claro! Já te mando os valores.' },
      ]);
    },

    async save({ name, ids }) {
      await wait(700);
      return { id: 9001, name, count: ids.length };
    },
  };
};
