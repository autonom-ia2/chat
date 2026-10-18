import { ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { fetchContactableInboxes } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { useNovaConversaContato } from '../useNovaConversaContato';

// #1459 — contato, canais e busca. O que importa aqui é a ordem das respostas
// do servidor: a de um contato antigo nunca pode cair no contato atual.
const estado = vi.hoisted(() => ({ buscar: null }));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    ref(
      nome === 'contacts/getContactById'
        ? id => ({ id: Number(id), name: `Contato ${id}` })
        : []
    ),
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async original => ({
    ...(await original()),
    fetchContactableInboxes: vi.fn(),
    createContactSearcher: () => estado.buscar,
    createNewContact: vi.fn(),
  })
);

const canal = (id, name) => ({ id, name, channelType: INBOX_TYPES.WEB });
const ANA = { id: 1, name: 'Ana' };
const BIA = { id: 2, name: 'Bia' };

// Uma promessa que o teste resolve (ou rejeita) quando quiser.
const adiada = () => {
  const controle = {};
  controle.promessa = new Promise((resolve, reject) => {
    Object.assign(controle, { resolve, reject });
  });
  return controle;
};

const comPedidos = quantos => {
  const pedidos = Array.from({ length: quantos }, adiada);
  pedidos.forEach(pedido =>
    fetchContactableInboxes.mockReturnValueOnce(pedido.promessa)
  );
  return pedidos;
};

describe('useNovaConversaContato', () => {
  beforeEach(() => {
    fetchContactableInboxes.mockReset();
    estado.buscar = vi.fn(async () => []);
  });

  describe('canais pedidos ao servidor', () => {
    it('fica com a resposta do contato atual quando elas chegam fora de ordem', async () => {
      const [daAna, daBia] = comPedidos(2);
      const tela = useNovaConversaContato();
      tela.escolherContato(ANA);
      tela.escolherContato(BIA);

      daBia.resolve([canal(20, 'Da Bia')]);
      await flushPromises();
      daAna.resolve([canal(10, 'Da Ana')]);
      await flushPromises();

      expect(tela.contato.value).toEqual(BIA);
      expect(tela.canais.value.map(item => item.name)).toEqual(['Da Bia']);
      expect(tela.canalId.value).toBe(20);
      expect(tela.carregandoCanais.value).toBe(false);
    });

    it('não desliga o "carregando" do contato atual quando o pedido antigo termina antes', async () => {
      const [daAna, daBia] = comPedidos(2);
      const tela = useNovaConversaContato();
      tela.escolherContato(ANA);
      tela.escolherContato(BIA);

      daAna.resolve([canal(10, 'Da Ana')]);
      await flushPromises();

      expect(tela.canais.value).toEqual([]);
      expect(tela.canalId.value).toBeNull();
      expect(tela.carregandoCanais.value).toBe(true);

      daBia.resolve([canal(20, 'Da Bia')]);
      await flushPromises();
      expect(tela.canalId.value).toBe(20);
      expect(tela.carregandoCanais.value).toBe(false);
    });

    it('ignora o erro de um pedido antigo que falha depois', async () => {
      const [daAna, daBia] = comPedidos(2);
      const tela = useNovaConversaContato();
      tela.escolherContato(ANA);
      tela.escolherContato(BIA);

      daBia.resolve([canal(20, 'Da Bia')]);
      await flushPromises();
      daAna.reject(new Error('caiu'));
      await flushPromises();

      expect(tela.erroNosCanais.value).toBe(false);
      expect(tela.canais.value.map(item => item.name)).toEqual(['Da Bia']);
      expect(tela.carregandoCanais.value).toBe(false);
    });

    it('ignora a resposta que chega depois de o contato ser limpo', async () => {
      const [daAna] = comPedidos(1);
      const tela = useNovaConversaContato();
      tela.escolherContato(ANA);
      tela.limparContato();
      expect(tela.carregandoCanais.value).toBe(false);

      daAna.resolve([canal(10, 'Da Ana')]);
      await flushPromises();

      expect(tela.contato.value).toBeNull();
      expect(tela.canais.value).toEqual([]);
      expect(tela.canalId.value).toBeNull();
    });

    it('avisa o erro quando o pedido do contato atual falha', async () => {
      const [daAna] = comPedidos(1);
      const tela = useNovaConversaContato();
      tela.escolherContato(ANA);

      daAna.reject(new Error('caiu'));
      await flushPromises();

      expect(tela.erroNosCanais.value).toBe(true);
      expect(tela.carregandoCanais.value).toBe(false);
    });

    it('mantém o canal escolhido ao recarregar os canais do mesmo contato', async () => {
      const lista = [canal(10, 'A'), canal(11, 'B')];
      fetchContactableInboxes.mockResolvedValue(lista);
      const tela = useNovaConversaContato();
      await tela.usarContatoDaPagina('1');
      tela.canalId.value = 11;

      await tela.usarContatoDaPagina('1');

      expect(tela.canalId.value).toBe(11);
      expect(tela.canais.value).toHaveLength(2);
    });

    // #1809: rascunho guardado na caixa A, "Escrever" aberto na caixa B: sai pela B.
    it('a gaveta aberta de outra caixa troca para a caixa nova', async () => {
      fetchContactableInboxes.mockResolvedValue([
        canal(10, 'A'),
        canal(11, 'B'),
      ]);
      const caixa = ref(10);
      const tela = useNovaConversaContato({
        caixaPreferida: () => caixa.value,
      });
      await tela.usarContatoDaPagina('1');
      expect(tela.canalId.value).toBe(10);

      caixa.value = 11;
      await flushPromises();

      expect(tela.canalId.value).toBe(11);
    });

    it('sem caixa pedida, a caixa escolhida pela pessoa fica', async () => {
      fetchContactableInboxes.mockResolvedValue([
        canal(10, 'A'),
        canal(11, 'B'),
      ]);
      const caixa = ref(10);
      const tela = useNovaConversaContato({
        caixaPreferida: () => caixa.value,
      });
      await tela.usarContatoDaPagina('1');
      tela.canalId.value = 11;

      caixa.value = null;
      await flushPromises();

      expect(tela.canalId.value).toBe(11);
    });
  });

  describe('busca', () => {
    beforeEach(() => {
      vi.useFakeTimers();
      fetchContactableInboxes.mockResolvedValue([]);
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('procura depois de a pessoa parar de digitar', async () => {
      estado.buscar = vi.fn(async () => [ANA]);
      const tela = useNovaConversaContato();

      tela.mudarTermo('ana');
      expect(tela.buscando.value).toBe(true);
      await vi.advanceTimersByTimeAsync(400);

      expect(estado.buscar).toHaveBeenCalledWith('ana');
      expect(tela.resultados.value).toEqual([ANA]);
      expect(tela.buscando.value).toBe(false);
    });

    it('cancela a busca que ainda ia sair quando a pessoa escolhe um contato', async () => {
      estado.buscar = vi.fn(async () => [BIA]);
      const tela = useNovaConversaContato();

      tela.mudarTermo('bia');
      tela.escolherContato(ANA);
      await vi.advanceTimersByTimeAsync(400);

      expect(estado.buscar).not.toHaveBeenCalledWith('bia');
      expect(tela.resultados.value).toEqual([]);
      expect(tela.buscando.value).toBe(false);
      expect(tela.termo.value).toBe('');
    });

    it('descarta o resultado de uma busca que já estava no ar', async () => {
      const noAr = adiada();
      estado.buscar = vi.fn(texto => (texto ? noAr.promessa : []));
      const tela = useNovaConversaContato();
      tela.mudarTermo('bia');
      await vi.advanceTimersByTimeAsync(400);

      tela.escolherContato(ANA);
      noAr.resolve([BIA]);
      await vi.advanceTimersByTimeAsync(0);

      // Sem texto, o buscador cancela o pedido que estiver no ar.
      expect(estado.buscar).toHaveBeenLastCalledWith('');
      expect(tela.resultados.value).toEqual([]);
      expect(tela.buscando.value).toBe(false);
    });
  });
});
