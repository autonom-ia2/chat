import { computed, reactive, ref } from 'vue';

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
});

export const payloadDoNegocio = form => ({
  title: form.title.trim(),
  description: form.description.trim(),
  value_cents: form.valueAmount
    ? Math.round(Number(form.valueAmount) * 100)
    : 0,
  currency: form.currency || 'BRL',
  priority: form.priority,
  score: Math.min(Math.max(Number(form.score || 0), 0), 100),
  expected_close_at: form.expectedCloseAt || null,
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
