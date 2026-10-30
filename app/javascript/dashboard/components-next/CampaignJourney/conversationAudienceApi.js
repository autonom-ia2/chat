// The search by conversation (#2277) as the screen sees it: plan → start → progress → result. The server keeps the
// search (planner and readers run in jobs); the screen polls it, so leaving and coming back finds it where it is.
import ConversationAudiencesAPI from 'dashboard/api/campaignJourneyConversationAudiences';

const POLL_MS = 3000;
// The planner takes ~20–60 s; past this the screen says it could not understand and lets the person try again.
const PLAN_TIMEOUT_MS = 4 * 60 * 1000;
const ANY = 'tanto-faz';

// Server status → the screen's state names (AudienceSearchReview / AudienceSearchStatus).
const STATES = {
  queued: 'fila',
  reading: 'lendo',
  done: 'pronto',
  saved: 'pronto',
  stopped: 'parado',
  ceiling: 'teto',
  failed: 'erro',
};
const READING = ['queued', 'reading'];
const PLANNING = 'planning';

const wait = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export class SearchError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

const person = item => ({
  id: item.id,
  name: item.name,
  contact: item.contact,
  confidence: item.confidence,
  reason: item.reason,
  conversationId: item.conversation_id,
});

const question = ({ text, options }) => ({
  text,
  options: options.map(label => ({ id: label, label })),
});

const planOf = search => ({
  understood: search.plan.understood,
  name: search.plan.name,
  conversations: search.plan.conversations,
  minutes: search.plan.minutes,
  cost: search.plan.cost,
  ceiling: search.plan.ceiling,
});

// What the "Confira" step shows for a search that finished planning.
const checkOf = search => {
  if (search.status === 'question')
    return { question: question(search.plan.question) };
  if (search.status === 'failed' && !search.plan?.cost) {
    throw new SearchError(search.error || 'plan_error');
  }
  return planOf(search);
};

// Queued with nobody else reading: the readers start on the next job, so the screen already says it is reading.
const stateOf = search => {
  if (search.status === 'queued' && !search.ahead_minutes) return 'lendo';
  return STATES[search.status] || 'lendo';
};

// Who was found, by id: a full answer replaces it, an answer with `since` brings only who changed (a person can move
// from the list to "left aside" and back, so each id lives in one of the two).
const createRoster = () => {
  const people = new Map();
  const aside = new Map();
  return {
    take(search, full) {
      if (full) {
        people.clear();
        aside.clear();
      }
      search.people.forEach(item => {
        aside.delete(item.id);
        people.set(item.id, person(item));
      });
      search.left_aside.forEach(([name, reason, id]) => {
        people.delete(id);
        aside.set(id, [name, reason, id]);
      });
    },
    people: () => [...people.values()].sort((a, b) => a.id - b.id),
    aside: () => [...aside.values()],
  };
};

export const createConversationAudienceApi = () => {
  let searchId = null;
  let timer = null;
  let cursor = null;
  const roster = createRoster();
  // Bumped when the screen leaves or starts over: a wait for the plan from before stops asking the server.
  let generation = 0;

  const fetchSearch = async () =>
    (await ConversationAudiencesAPI.show(searchId)).data;

  // The progress of the search, people merged in the roster. `full` reads the whole list (opening, and the end,
  // when a conversation the person can no longer open may have left it).
  const snapshot = (search, full) => {
    roster.take(search, full);
    cursor = search.cursor;
    return {
      state: stateOf(search),
      error: search.error,
      read: search.read,
      total: search.total,
      people: roster.people(),
      cost: search.cost,
      leftAside: roster.aside(),
      skipped: search.skipped || 0,
      aheadMinutes: search.ahead_minutes,
      finishing: Boolean(search.finishing),
    };
  };

  const fetchSince = async () =>
    (await ConversationAudiencesAPI.show(searchId, cursor)).data;

  const untilPlanned = async () => {
    const mine = generation;
    const deadline = Date.now() + PLAN_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (mine !== generation) throw new SearchError('left');
      // eslint-disable-next-line no-await-in-loop
      const search = await fetchSearch();
      if (search.status !== PLANNING) return checkOf(search);
      // eslint-disable-next-line no-await-in-loop
      await wait(POLL_MS);
    }
    throw new SearchError('plan_timeout');
  };

  const stopPolling = () => {
    clearTimeout(timer);
    timer = null;
  };

  return {
    async status() {
      const { data } = await ConversationAudiencesAPI.status();
      return {
        hasOwnKey: data.has_own_key,
        periods: data.periods,
        openSearchId: data.open_search_id,
      };
    },

    // A new request creates the search; the answer to the question goes to the same search.
    async plan({ request, period, answer, anyLabel }) {
      if (answer && searchId) {
        const text = answer === ANY ? anyLabel : answer;
        await ConversationAudiencesAPI.answer(searchId, text);
      } else {
        const { data } = await ConversationAudiencesAPI.create({
          request,
          period,
        });
        searchId = data.id;
      }
      return untilPlanned();
    },

    // A search left open (the person left the screen, or came from the bell): where it stands.
    async open(id) {
      searchId = id;
      const search = await fetchSearch();
      const base = { request: search.request, period: search.period };
      if (search.status === PLANNING)
        return { ...base, check: await untilPlanned() };
      if (['question', 'planned'].includes(search.status)) {
        return { ...base, check: checkOf(search) };
      }
      // Saved already, or never planned: the screen starts a new request.
      if (search.status === 'saved' || !search.plan?.cost) return null;
      return {
        ...base,
        plan: planOf(search),
        progress: snapshot(search, true),
      };
    },

    // In line only when another search of the account is reading (the server says for about how long).
    async start() {
      const { data } = await ConversationAudiencesAPI.start(searchId);
      cursor = null;
      return {
        queued: Boolean(data.ahead_minutes),
        aheadMinutes: data.ahead_minutes,
      };
    },

    // Polls the search while the readers go; people appear as they are found. After "Parar", it goes on until the
    // wave in flight writes who it found; the last read is the whole list.
    watch(_plan, onChange) {
      stopPolling();
      const mine = generation;
      const tick = async () => {
        const full = cursor === null;
        const search = await fetchSince();
        if (mine !== generation) return;
        if (READING.includes(search.status) || search.finishing) {
          onChange(snapshot(search, full));
          timer = setTimeout(tick, POLL_MS);
          return;
        }
        const last = await fetchSearch();
        if (mine === generation) onChange(snapshot(last, true));
      };
      timer = setTimeout(tick, POLL_MS);
    },

    // "Continuar" after the ceiling, the AI or "Parar": goes on from the next batch not read.
    async resume(plan, onChange) {
      await ConversationAudiencesAPI.resume(searchId);
      this.watch(plan, onChange);
    },

    // Stops the readers; who was found so far stays. The list keeps updating (watch) until the wave in flight ends.
    async stop() {
      if (searchId) await ConversationAudiencesAPI.stop(searchId);
    },

    // Gives up while still in line: the plan comes back and nothing more is read.
    async giveUp() {
      generation += 1;
      stopPolling();
      if (searchId) await ConversationAudiencesAPI.stop(searchId);
    },

    // Leaving the screen: the search keeps going on the server.
    detach() {
      generation += 1;
      stopPolling();
    },

    // Back to the request: the next request starts a new search.
    reset() {
      generation += 1;
      stopPolling();
      searchId = null;
      cursor = null;
    },

    async conversation(personId) {
      const { data } = await ConversationAudiencesAPI.conversation(
        searchId,
        personId
      );
      return data.payload;
    },

    async save({ name, ids }) {
      const { data } = await ConversationAudiencesAPI.save(searchId, {
        name,
        personIds: ids,
      });
      return data;
    },
  };
};
