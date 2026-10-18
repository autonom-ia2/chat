import { reactive, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useModeloDoEmailNaGaveta } from '../useModeloDoEmailNaGaveta';

// #1809 — continuando uma conversa (#1505), o modelo é preenchido pela conversa (como na
// resposta, com a IA) e o histórico vai no fim; numa conversa nova, pelo contato e sem
// histórico. Trocar de contato no meio da espera não põe o modelo no rascunho do outro.
const api = vi.hoisted(() => ({ abrir: vi.fn(), abrirParaContato: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/modelosDeEmail', () => ({ default: api }));
vi.mock('dashboard/helper/compileEmailMjml', () => ({
  compileEmailMjml: async () => '',
}));

const DADOS = {
  id: 5,
  nome: 'Proposta',
  html: '<html><head></head><body><p>Oi {{ nome }}</p></body></html>',
  campos: [{ chave: 'nome', valor: 'Ana', origem: 'ia' }],
};

const montar = ({ conversa = null } = {}) => {
  const form = reactive({ modeloDoEmail: null, valoresDoModelo: {} });
  const contato = ref({ id: 9 });
  const canal = ref({ id: 4 });
  const destino = ref(conversa);
  const ultimaMensagemId = ref(conversa ? 300 : null);
  const modelo = useModeloDoEmailNaGaveta({
    form,
    contato,
    canal,
    destino,
    ultimaMensagemId,
  });
  return { form, contato, modelo };
};

beforeEach(() => {
  api.abrir.mockReset().mockResolvedValue({ data: DADOS });
  api.abrirParaContato.mockReset().mockResolvedValue({ data: DADOS });
});

describe('useModeloDoEmailNaGaveta', () => {
  it('continuando, abre pela conversa e manda o histórico junto', async () => {
    const { form, modelo } = montar({ conversa: { displayId: 31 } });
    await modelo.escolher(5);
    await flushPromises();

    expect(api.abrir).toHaveBeenCalledWith(5, 31);
    expect(api.abrirParaContato).not.toHaveBeenCalled();
    expect(form.valoresDoModelo).toEqual({ nome: 'Ana' });
    const { atributos } = modelo.noEnvio('Bom dia');
    expect(atributos.email_citacao).toEqual({
      tipo: 'historico',
      message_id: 300,
    });
    expect(atributos.email_modelo.html).toContain('Oi Ana');
  });

  it('conversa nova: pelo contato, sem histórico', async () => {
    const { modelo } = montar();
    await modelo.escolher(5);
    await flushPromises();

    expect(api.abrirParaContato).toHaveBeenCalledWith(5, {
      contactId: 9,
      inboxId: 4,
    });
    expect(modelo.noEnvio('x').atributos.email_citacao).toBeUndefined();
  });

  it('trocou de contato antes de o modelo chegar: o modelo não entra', async () => {
    const { form, contato, modelo } = montar();
    const espera = modelo.escolher(5);
    contato.value = { id: 10 };
    await espera;
    await flushPromises();
    expect(form.modeloDoEmail).toBeNull();
  });

  it('sem modelo, o envio segue como antes', () => {
    const { modelo } = montar();
    expect(modelo.noEnvio('Oi')).toEqual({ mensagem: 'Oi', atributos: null });
  });
});

describe('useModeloDoEmailNaGaveta: respostas fora de ordem', () => {
  const adiado = () => {
    let soltar;
    const promessa = new Promise(resolver => {
      soltar = resolver;
    });
    return { promessa, soltar };
  };

  it('duas escolhas seguidas: vale a última, mesmo que a primeira chegue depois', async () => {
    const primeira = adiado();
    const segunda = adiado();
    api.abrirParaContato
      .mockReturnValueOnce(primeira.promessa)
      .mockReturnValueOnce(segunda.promessa);
    const { form, modelo } = montar();
    const a = modelo.escolher(1);
    const b = modelo.escolher(2);
    segunda.soltar({ data: { ...DADOS, id: 2, nome: 'Segundo' } });
    await b;
    primeira.soltar({ data: { ...DADOS, id: 1, nome: 'Primeiro' } });
    await a;
    await flushPromises();
    expect(form.modeloDoEmail.nome).toBe('Segundo');
  });

  it('"Tirar o modelo" com o pedido a caminho: ele não volta', async () => {
    const pedido = adiado();
    api.abrirParaContato.mockReturnValueOnce(pedido.promessa);
    const { form, modelo } = montar();
    const espera = modelo.escolher(5);
    modelo.tirar();
    pedido.soltar({ data: DADOS });
    await espera;
    await flushPromises();
    expect(form.modeloDoEmail).toBeNull();
  });
});
