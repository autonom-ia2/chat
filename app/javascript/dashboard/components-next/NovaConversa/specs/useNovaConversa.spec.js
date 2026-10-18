import { nextTick, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useNovaConversa } from '../useNovaConversa';

// #1459 — a mensagem e o envio. O que foi escrito para uma pessoa nunca segue
// para outra, e dois envios não saem ao mesmo tempo.
const estado = vi.hoisted(() => ({ dispatch: null }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      getCurrentUser: { id: 3 },
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
      // #1809: caixa sem a conversa de e-mail nova (sem histórico).
      'inboxes/getInbox': () => ({}),
      'accounts/isFeatureEnabledonAccount': () => false,
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));

const ANA = { id: 1, name: 'Ana' };
const BIA = { id: 2, name: 'Bia' };
const EMAIL = { id: 4, name: 'Contato', channelType: INBOX_TYPES.EMAIL };
const SITE = { id: 5, name: 'Loja', channelType: INBOX_TYPES.WEB };
const TWILIO = {
  id: 6,
  name: 'Twilio',
  channelType: INBOX_TYPES.TWILIO,
  medium: 'whatsapp',
};

const montar = (contatoInicial = ANA, canalInicial = EMAIL) => {
  const contato = ref(contatoInicial);
  const canal = ref(canalInicial);
  return { contato, canal, ...useNovaConversa({ contato, canal }) };
};

const escrever = form =>
  Object.assign(form, {
    mensagem: 'Segredo da Ana',
    assunto: 'Proposta da Ana',
    cc: 'chefe@ana.com',
    bcc: 'oculto@ana.com',
    anexos: [{ resource: { id: 1 } }],
    modelo: { name: 'boas_vindas' },
    camposProntos: true,
    textoDoModelo: 'Oi, Ana',
    modo: 'pronta',
  });

const VAZIO = {
  modo: 'escrever',
  mensagem: '',
  assunto: '',
  cc: '',
  bcc: '',
  anexos: [],
  modelo: null,
  camposProntos: false,
  textoDoModelo: '',
  modeloDoEmail: null,
  valoresDoModelo: {},
  historicoDesligado: false,
};

describe('useNovaConversa', () => {
  beforeEach(() => {
    estado.dispatch = vi.fn(async () => ({ id: 42, account_id: 7 }));
  });

  describe('o que foi escrito para um contato', () => {
    it('some inteiro quando o contato muda', async () => {
      const tela = montar();
      escrever(tela.form);
      tela.erro.value = 'falhou';

      tela.contato.value = BIA;
      await nextTick();

      expect({ ...tela.form }).toEqual(VAZIO);
      expect(tela.erro.value).toBe('');
    });

    it('some inteiro quando o contato e o canal mudam juntos', async () => {
      const tela = montar();
      escrever(tela.form);

      // É o que a tela faz ao trocar de contato: solta o canal e troca.
      tela.canal.value = null;
      tela.contato.value = BIA;
      await nextTick();
      tela.canal.value = SITE;
      await nextTick();

      expect({ ...tela.form }).toEqual(VAZIO);
    });

    it('some inteiro quando o contato é limpo', async () => {
      const tela = montar();
      escrever(tela.form);

      tela.canal.value = null;
      tela.contato.value = null;
      await nextTick();

      expect({ ...tela.form }).toEqual(VAZIO);
    });

    it('fica quando só o canal do mesmo contato muda (menos o que era do canal)', async () => {
      const tela = montar();
      escrever(tela.form);

      tela.canal.value = SITE;
      await nextTick();

      expect(tela.form.mensagem).toBe('Segredo da Ana');
      expect(tela.form.assunto).toBe('Proposta da Ana');
      expect(tela.form.cc).toBe('chefe@ana.com');
      expect(tela.form.bcc).toBe('oculto@ana.com');
      expect(tela.form.anexos).toEqual([]);
      expect(tela.form.modelo).toBeNull();
    });

    it('fica quando o mesmo contato chega de novo (reabrir a gaveta)', async () => {
      const tela = montar();
      escrever(tela.form);

      tela.contato.value = { ...ANA };
      tela.canal.value = { ...EMAIL };
      await nextTick();

      expect(tela.form.mensagem).toBe('Segredo da Ana');
      expect(tela.form.modelo).toEqual({ name: 'boas_vindas' });
    });
  });

  describe('envio', () => {
    const PRONTA = {
      message: 'Oi!',
      templateParams: { name: 'boas_vindas' },
    };
    const envios = () =>
      estado.dispatch.mock.calls.filter(
        ([acao]) => acao === 'contactConversations/create'
      );

    it('não manda a mensagem pronta duas vezes enquanto a primeira está no ar', async () => {
      let terminar;
      estado.dispatch = vi.fn(
        () =>
          new Promise(resolve => {
            terminar = () => resolve({ id: 42, account_id: 7 });
          })
      );
      const tela = montar(ANA, TWILIO);

      tela.enviarPronta(PRONTA);
      tela.enviarPronta(PRONTA);
      expect(tela.enviando.value).toBe(true);
      expect(envios()).toHaveLength(1);

      terminar();
      await flushPromises();
      expect(tela.enviando.value).toBe(false);
      expect(tela.enviada.value.id).toBe(42);
    });

    it('deixa enviar de novo depois de uma falha', async () => {
      estado.dispatch = vi
        .fn()
        .mockRejectedValueOnce(new Error('falhou'))
        .mockResolvedValueOnce({ id: 43, account_id: 7 });
      const tela = montar(ANA, TWILIO);

      await tela.enviarPronta(PRONTA);
      expect(tela.erro.value).toBe('NOVA_CONVERSA.ERRO.PADRAO');
      await tela.enviarPronta(PRONTA);

      expect(envios()).toHaveLength(2);
      expect(tela.enviada.value.id).toBe(43);
    });

    it('guarda o assunto e o canal do e-mail enviado para a confirmação', async () => {
      const tela = montar(ANA, { ...EMAIL, email: 'oi@loja.com' });
      Object.assign(tela.form, { mensagem: '**Oi**', assunto: 'Proposta' });

      await tela.enviar(() => null);

      expect(tela.enviada.value).toMatchObject({
        nome: 'Ana',
        texto: '**Oi**',
        assunto: 'Proposta',
        email: true,
        chaveDoCanal: 'EMAIL',
        caixa: 'Contato',
        endereco: 'oi@loja.com',
      });
      expect(tela.form.mensagem).toBe('');
    });
  });
});
