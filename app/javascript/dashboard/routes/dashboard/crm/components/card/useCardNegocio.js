import { computed, reactive, ref } from 'vue';

// #1498 — Cobrança: o dia em que o cliente prometeu pagar (metadata do card).
// Logo depois de salvar, o card local traz o campo solto (payment_promise_at).
export const promessaDoCard = card => {
  const valor =
    card && 'payment_promise_at' in card
      ? card.payment_promise_at
      : card?.metadata?.payment_promise_at;
  return valor ? String(valor).slice(0, 10) : '';
};

// #1423 — os dados do negócio no card: nome, observações, quanto vale (moeda
// e valor), urgência, quanto pede atenção (0 a 100) e quando deve fechar. Os
// campos e o envio são os mesmos da gaveta antiga (RS-03 a RS-08).
export const MOEDAS = ['BRL', 'USD', 'EUR'];
export const URGENCIAS = ['low', 'medium', 'high', 'urgent'];

const vazio = () => ({
  title: '',
  description: '',
  valueAmount: '',
  currency: 'BRL',
  priority: 'medium',
  score: 0,
  expectedCloseAt: '',
  paymentPromiseAt: '',
});

export const negocioDoCard = card => ({
  title: card?.title || '',
  description: card?.description || '',
  valueAmount: card?.value_cents ? Number(card.value_cents) / 100 : '',
  currency: card?.currency || 'BRL',
  priority: card?.priority || 'medium',
  score: card?.score || 0,
  expectedCloseAt: card?.expected_close_at
    ? card.expected_close_at.slice(0, 10)
    : '',
  paymentPromiseAt: promessaDoCard(card),
});

// `cobranca`: só a Cobrança mexe na promessa de pagamento; os outros cards
// não mandam o campo (e não apagam uma promessa antiga).
// `valorOculto` (#2075): sem a chave de valores a pessoa não vê o valor, então
// não manda valor nem moeda (o servidor também descarta).
const valorDoNegocio = form => ({
  value_cents: form.valueAmount
    ? Math.round(Number(form.valueAmount) * 100)
    : 0,
  currency: form.currency || 'BRL',
});

export const payloadDoNegocio = (
  form,
  { cobranca = false, valorOculto = false } = {}
) => ({
  title: form.title.trim(),
  description: form.description.trim(),
  ...(valorOculto ? {} : valorDoNegocio(form)),
  priority: form.priority,
  score: Math.min(Math.max(Number(form.score || 0), 0), 100),
  expected_close_at: form.expectedCloseAt || null,
  ...(cobranca ? { payment_promise_at: form.paymentPromiseAt || null } : {}),
});

export const useCardNegocio = () => {
  const form = reactive(vazio());
  const foto = ref(JSON.stringify(vazio()));
  const sujo = computed(() => JSON.stringify({ ...form }) !== foto.value);
  const valido = computed(() => Boolean(form.title.trim()));
  const carregar = card => {
    Object.assign(form, negocioDoCard(card));
    foto.value = JSON.stringify({ ...form });
  };
  const desfazer = () => Object.assign(form, JSON.parse(foto.value));
  return { form, sujo, valido, carregar, desfazer };
};
