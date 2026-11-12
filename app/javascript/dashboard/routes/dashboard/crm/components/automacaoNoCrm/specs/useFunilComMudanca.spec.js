import { nextTick, reactive, ref } from 'vue';
import { useFunilComMudanca } from '../useFunilComMudanca';

// #2414 F6.5 — a gaveta "Editar funil" sabe se tem mudança não salva: o formulário e as frases das etapas contra o
// retrato de quando abriu; a contagem de cards (tempo real) não conta.
const montar = () => {
  const form = reactive({
    name: 'Vendas',
    stages: [{ id: 1, name: 'Novo', total_cards_count: 2 }],
  });
  const aiPanel = ref(null);
  const frasesProntas = ref(false);
  const sessao = ref(1);
  const mudou = useFunilComMudanca({ form, aiPanel, frasesProntas, sessao });
  return { form, aiPanel, frasesProntas, sessao, mudou };
};

describe('useFunilComMudanca', () => {
  it('nasce sem mudança e acusa a mudança no nome ou numa etapa', () => {
    const { form, mudou } = montar();
    expect(mudou.value).toBe(false);
    form.stages[0].name = 'Novo contato';
    expect(mudou.value).toBe(true);
    form.stages[0].name = 'Novo';
    form.name = 'Vendas 2';
    expect(mudou.value).toBe(true);
  });

  it('a contagem de cards que o tempo real atualiza não conta', () => {
    const { form, mudou } = montar();
    form.stages[0].total_cards_count = 9;
    expect(mudou.value).toBe(false);
  });

  it('as frases contam a partir de quando ficam prontas', async () => {
    const { aiPanel, frasesProntas, mudou } = montar();
    aiPanel.value = { form: { stageCriteria: { 1: 'Pediu orçamento' } } };
    frasesProntas.value = true;
    await nextTick();
    expect(mudou.value).toBe(false);
    aiPanel.value.form.stageCriteria[1] = 'Pediu orçamento por WhatsApp';
    expect(mudou.value).toBe(true);
  });

  it('abrir a gaveta de novo tira um retrato novo', async () => {
    const { form, sessao, mudou } = montar();
    form.name = 'Outro funil';
    expect(mudou.value).toBe(true);
    sessao.value += 1;
    await nextTick();
    expect(mudou.value).toBe(false);
  });
});
