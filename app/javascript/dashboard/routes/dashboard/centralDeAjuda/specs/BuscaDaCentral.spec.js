import { mount, flushPromises } from '@vue/test-utils';
import BuscaDaCentral from '../components/BuscaDaCentral.vue';

const pedirAoGuia = vi.fn();
const buscar = vi.fn();
const buscarInteligente = vi.fn();
const push = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valor) =>
      typeof valor === 'number' ? `${chave}:${valor}` : chave,
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useGuiaPedido', () => ({
  useGuiaPedido: () => ({ pedirAoGuia }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: {
    buscar: (...args) => buscar(...args),
    buscarInteligente: (...args) => buscarInteligente(...args),
  },
}));

const ESPERA_DAS_DUAS_BUSCAS_MS = 500;
// Teto da espera pela Melhor resposta (1500 ms do pedido ao Jev), com folga.
const TETO_MS = 1600;
const ROTULO_DO_CARTAO = 'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.MELHOR_RESPOSTA';

const artigo = (id, titulo) => ({
  id,
  ref: id.replace('.', '-'),
  titulo,
  descricao: `Sobre ${titulo}`,
  capitulo: 'Capítulo',
});
const WHATSAPP = artigo('07.08', 'Conectar o WhatsApp');
const SENHA = artigo('01.02', 'Trocar a senha');
const FUNIL = artigo('03.01', 'Criar um funil');

const montar = (props = {}) =>
  mount(BuscaDaCentral, {
    props,
    global: {
      stubs: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        Spinner: true,
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const digitar = async (tela, texto) => {
  await tela.find('input').setValue(texto);
  await vi.advanceTimersByTimeAsync(ESPERA_DAS_DUAS_BUSCAS_MS);
  await flushPromises();
};

const cartao = tela =>
  tela.findAll('a').find(link => link.text().includes(ROTULO_DO_CARTAO));
const itensDaLista = tela => tela.findAll('li').map(item => item.text());
const anuncio = tela => tela.find('[aria-live="polite"]').text();

const botaoDoGuia = tela =>
  tela
    .findAll('button')
    .find(botao =>
      botao.text().includes('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PERGUNTAR_GUIA')
    );

// Pedidos da Melhor resposta, sem os da alternativa (que levam `exceto`, #985).
const pedidosDaMelhor = () =>
  buscarInteligente.mock.calls.filter(([, exceto]) => !exceto).length;

// Promessa que o teste resolve quando quiser: simula a resposta que chega fora de ordem.
const adiada = () => {
  let resolver;
  const promessa = new Promise(ok => {
    resolver = ok;
  });
  return { promessa, resolver };
};

describe('BuscaDaCentral', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    pedirAoGuia.mockClear();
    push.mockClear();
    buscar.mockReset();
    buscarInteligente.mockReset();
    buscar.mockResolvedValue({ data: { resultados: [] } });
    buscarInteligente.mockResolvedValue({
      data: { melhor: null, certeza: null },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('manda o texto digitado como pergunta ao Guia', async () => {
    const tela = montar({ guiaDisponivel: true });

    await tela.find('input').setValue('como conectar o whatsapp');
    await botaoDoGuia(tela).trigger('click');

    expect(pedirAoGuia).toHaveBeenCalledWith('como conectar o whatsapp');
  });

  it('com a busca vazia, o botão só abre o Guia', async () => {
    const tela = montar({ guiaDisponivel: true });

    await botaoDoGuia(tela).trigger('click');

    expect(pedirAoGuia).toHaveBeenCalledWith('');
  });

  it('esconde o botão quando o Guia não está disponível', async () => {
    const tela = montar({ guiaDisponivel: false });
    await flushPromises();

    expect(botaoDoGuia(tela)).toBeUndefined();
  });

  it('com certeza alta mostra o cartão e não repete o artigo na lista', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA, WHATSAPP] } });
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.9 },
    });
    const tela = montar();

    await digitar(tela, 'não chega mensagem');

    expect(cartao(tela).text()).toContain(WHATSAPP.titulo);
    expect(itensDaLista(tela)).toHaveLength(1);
    expect(itensDaLista(tela)[0]).toContain(SENHA.titulo);
    expect(anuncio(tela)).toContain('ANUNCIO_MELHOR');
    expect(anuncio(tela)).toContain('RESULTADOS:2');
  });

  it('com certeza baixa põe o artigo no topo da lista, sem cartão e sem repetir', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA, WHATSAPP] } });
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.2 },
    });
    const tela = montar();

    await digitar(tela, 'não chega mensagem');

    expect(cartao(tela)).toBeUndefined();
    const itens = itensDaLista(tela);
    expect(itens).toHaveLength(2);
    expect(itens[0]).toContain(WHATSAPP.titulo);
    expect(itens[1]).toContain(SENHA.titulo);
  });

  it('ignora a resposta atrasada de um termo antigo', async () => {
    const antiga = adiada();
    const nova = adiada();
    buscarInteligente
      .mockReturnValueOnce(antiga.promessa)
      .mockReturnValueOnce(nova.promessa);
    const tela = montar();

    await digitar(tela, 'whatsapp');
    await digitar(tela, 'senha');
    nova.resolver({ data: { melhor: SENHA, certeza: 0.9 } });
    await flushPromises();
    antiga.resolver({ data: { melhor: WHATSAPP, certeza: 0.95 } });
    await flushPromises();

    expect(buscarInteligente).toHaveBeenNthCalledWith(1, 'whatsapp');
    expect(buscarInteligente).toHaveBeenNthCalledWith(2, 'senha');
    expect(cartao(tela).text()).toContain(SENHA.titulo);
    expect(tela.text()).not.toContain(WHATSAPP.titulo);
  });

  it('se a busca inteligente falha, a lista por palavras continua sem alerta', async () => {
    buscar.mockResolvedValue({ data: { resultados: [FUNIL] } });
    buscarInteligente.mockRejectedValue(new Error('timeout'));
    const tela = montar();

    await digitar(tela, 'criar funil');

    expect(itensDaLista(tela)[0]).toContain(FUNIL.titulo);
    expect(cartao(tela)).toBeUndefined();
    expect(tela.text()).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ERRO'
    );
  });

  it('Enter abre a melhor resposta, não o primeiro da lista', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.6 },
    });
    const tela = montar();

    await digitar(tela, 'não chega mensagem');
    await tela.find('input').trigger('keydown.enter');

    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: WHATSAPP.ref },
    });
  });

  it('sem melhor resposta, Enter abre o primeiro da lista', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
    const tela = montar();

    await digitar(tela, 'senha');
    await tela.find('input').trigger('keydown.enter');

    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: SENHA.ref },
    });
  });

  it('com menos de 3 letras não chama a busca inteligente', async () => {
    const tela = montar();

    await digitar(tela, 'wa');

    expect(buscar).toHaveBeenCalledWith('wa');
    expect(buscarInteligente).not.toHaveBeenCalled();
  });

  it('segura a lista até a inteligente voltar: o cartão não empurra o que a pessoa ia tocar', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA, WHATSAPP] } });
    const inteligente = adiada();
    buscarInteligente.mockReturnValue(inteligente.promessa);
    const tela = montar();

    await digitar(tela, 'não chega mensagem');

    expect(itensDaLista(tela)).toHaveLength(0);
    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PROCURANDO_MELHOR'
    );

    inteligente.resolver({ data: { melhor: WHATSAPP, certeza: 0.9 } });
    await flushPromises();

    expect(cartao(tela).text()).toContain(WHATSAPP.titulo);
    expect(itensDaLista(tela)).toEqual([expect.stringContaining(SENHA.titulo)]);
  });

  it('passado o teto, mostra a lista e ignora a Melhor resposta atrasada', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
    const inteligente = adiada();
    buscarInteligente.mockReturnValue(inteligente.promessa);
    const tela = montar();

    await digitar(tela, 'senha');
    await vi.advanceTimersByTimeAsync(TETO_MS);

    expect(itensDaLista(tela)[0]).toContain(SENHA.titulo);
    inteligente.resolver({ data: { melhor: WHATSAPP, certeza: 0.9 } });
    await flushPromises();

    expect(cartao(tela)).toBeUndefined();
    expect(itensDaLista(tela)).toEqual([expect.stringContaining(SENHA.titulo)]);
  });

  it('sem lista por palavras, espera a inteligente mesmo depois do teto', async () => {
    const inteligente = adiada();
    buscarInteligente.mockReturnValue(inteligente.promessa);
    const tela = montar();

    await digitar(tela, 'cliente não recebe minha mensagem');
    await vi.advanceTimersByTimeAsync(TETO_MS);

    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.PROCURANDO_MELHOR'
    );
    inteligente.resolver({ data: { melhor: WHATSAPP, certeza: 0.8 } });
    await flushPromises();

    expect(cartao(tela).text()).toContain(WHATSAPP.titulo);
  });

  it('anuncia uma frase só por busca, sem o estado do meio', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
    const inteligente = adiada();
    buscarInteligente.mockReturnValue(inteligente.promessa);
    const tela = montar();

    await digitar(tela, 'senha');
    expect(anuncio(tela)).toBe('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.BUSCANDO');

    inteligente.resolver({ data: { melhor: SENHA, certeza: 0.9 } });
    await flushPromises();

    expect(anuncio(tela)).toBe(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ANUNCIO_MELHOR HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.RESULTADOS:1'
    );
  });

  it('Enter logo depois de digitar busca na hora e abre a Melhor resposta quando chega', async () => {
    buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.7 },
    });
    const tela = montar();

    await tela.find('input').setValue('não chega mensagem');
    await tela.find('input').trigger('keydown.enter');
    await flushPromises();

    expect(buscar).toHaveBeenCalledOnce();
    expect(pedidosDaMelhor()).toBe(1);
    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: WHATSAPP.ref },
    });
    await vi.advanceTimersByTimeAsync(ESPERA_DAS_DUAS_BUSCAS_MS);
    expect(buscar).toHaveBeenCalledOnce();
    expect(pedidosDaMelhor()).toBe(1);
  });

  it('Enter com a inteligente lenta abre o 1º da lista nova quando passa o teto', async () => {
    buscar.mockResolvedValue({ data: { resultados: [FUNIL] } });
    buscarInteligente.mockReturnValue(adiada().promessa);
    const tela = montar();

    await tela.find('input').setValue('criar funil');
    await tela.find('input').trigger('keydown.enter');
    await flushPromises();
    expect(push).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(TETO_MS);

    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: FUNIL.ref },
    });
  });

  it('com a busca por palavras em erro, mostra a escolha do Jev e não a mensagem de erro', async () => {
    buscar.mockRejectedValue(new Error('500'));
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.2 },
    });
    const tela = montar();

    await digitar(tela, 'não chega mensagem');

    expect(itensDaLista(tela)).toEqual([
      expect.stringContaining(WHATSAPP.titulo),
    ]);
    expect(tela.text()).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ERRO'
    );
  });

  it('com as duas falhando, mostra a mensagem de erro', async () => {
    buscar.mockRejectedValue(new Error('500'));
    buscarInteligente.mockRejectedValue(new Error('500'));
    const tela = montar();

    await digitar(tela, 'whatsapp');

    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ERRO');
  });

  it('espaço a mais não apaga o cartão nem busca de novo', async () => {
    buscarInteligente.mockResolvedValue({
      data: { melhor: WHATSAPP, certeza: 0.9 },
    });
    const tela = montar();

    await digitar(tela, 'conectar whatsapp');
    await digitar(tela, 'conectar whatsapp ');

    expect(cartao(tela).text()).toContain(WHATSAPP.titulo);
    expect(buscar).toHaveBeenCalledOnce();
    expect(pedidosDaMelhor()).toBe(1);
  });

  it('"Nada encontrado" só quando as duas buscas voltam vazias', async () => {
    const inteligente = adiada();
    buscarInteligente.mockReturnValue(inteligente.promessa);
    const tela = montar({ guiaDisponivel: true });

    await digitar(tela, 'xpto qualquer');
    expect(tela.text()).not.toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.NADA'
    );

    inteligente.resolver({ data: { melhor: null, certeza: null } });
    await flushPromises();

    expect(tela.text()).toContain('HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.NADA');
    expect(tela.text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.PERGUNTE'
    );
  });
  describe('alternativa e outros resultados (#985)', () => {
    const ROTULO_ALTERNATIVA =
      'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.TAMBEM_AJUDA';
    const ROTULO_OUTROS = 'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.OUTROS';
    const CONTATOS = artigo('09.01', 'Ver os contatos');
    const RELATORIO = artigo('14.01', 'Abrir os relatórios');

    const responder = ({ melhor, alternativa, certeza = 0.9 }) =>
      buscarInteligente.mockImplementation((termo, exceto) =>
        Promise.resolve({
          data: exceto
            ? { melhor: alternativa, certeza: alternativa ? certeza : null }
            : { melhor, certeza },
        })
      );
    const cartaoDaAlternativa = tela =>
      tela.findAll('a').find(link => link.text().includes(ROTULO_ALTERNATIVA));

    it('mostra a alternativa abaixo da resposta, sem repetir, e a pede excluindo a resposta', async () => {
      buscar.mockResolvedValue({
        data: { resultados: [SENHA, WHATSAPP, FUNIL] },
      });
      responder({ melhor: WHATSAPP, alternativa: FUNIL });
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');

      expect(buscarInteligente).toHaveBeenCalledWith(
        'como conecto meu zap',
        WHATSAPP.id
      );
      expect(cartao(tela).text()).toContain(WHATSAPP.titulo);
      expect(cartaoDaAlternativa(tela).text()).toContain(FUNIL.titulo);
      expect(itensDaLista(tela).join(' ')).not.toContain(FUNIL.titulo);
      expect(itensDaLista(tela).join(' ')).not.toContain(WHATSAPP.titulo);
    });

    it('com a resposta em destaque, a busca por palavras vira Outros resultados com no máximo 3', async () => {
      buscar.mockResolvedValue({
        data: { resultados: [WHATSAPP, SENHA, FUNIL, CONTATOS, RELATORIO] },
      });
      responder({ melhor: WHATSAPP, alternativa: null });
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');

      expect(tela.text()).toContain(ROTULO_OUTROS);
      expect(itensDaLista(tela)).toHaveLength(3);
      expect(cartaoDaAlternativa(tela)).toBeUndefined();
    });

    it('alternativa com certeza baixa não aparece', async () => {
      buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
      buscarInteligente.mockImplementation((termo, exceto) =>
        Promise.resolve({
          data: exceto
            ? { melhor: FUNIL, certeza: 0.2 }
            : { melhor: WHATSAPP, certeza: 0.9 },
        })
      );
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');

      expect(cartao(tela)).toBeDefined();
      expect(cartaoDaAlternativa(tela)).toBeUndefined();
    });

    it('sem resposta em destaque, a lista continua inteira e sem o título Outros resultados', async () => {
      buscar.mockResolvedValue({
        data: { resultados: [SENHA, FUNIL, CONTATOS, RELATORIO] },
      });
      responder({ melhor: null, alternativa: null });
      const tela = montar();
      await digitar(tela, 'trocar senha');

      expect(tela.text()).not.toContain(ROTULO_OUTROS);
      expect(itensDaLista(tela)).toHaveLength(4);
      expect(pedidosDaMelhor()).toBe(1);
      expect(buscarInteligente).toHaveBeenCalledTimes(1);
    });

    it('não pede a alternativa quando a Melhor resposta não fica em destaque', async () => {
      buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
      responder({ melhor: WHATSAPP, alternativa: FUNIL, certeza: 0.2 });
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');

      expect(buscarInteligente).toHaveBeenCalledTimes(1);
      expect(cartaoDaAlternativa(tela)).toBeUndefined();
    });

    it('com Enter, abre a Melhor resposta e não pede a alternativa', async () => {
      buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
      responder({ melhor: WHATSAPP, alternativa: FUNIL });
      const tela = montar();
      await tela.find('input').setValue('como conecto meu zap');
      await tela.find('input').trigger('keydown.enter');
      await flushPromises();

      expect(push).toHaveBeenCalledWith({
        name: 'central_de_ajuda_artigo',
        params: { ref: WHATSAPP.ref },
      });
      expect(buscarInteligente).toHaveBeenCalledTimes(1);
    });

    it('a tela espera a alternativa e mostra tudo junto: a lista não muda depois de aparecer', async () => {
      buscar.mockResolvedValue({
        data: { resultados: [WHATSAPP, SENHA, FUNIL, CONTATOS, RELATORIO] },
      });
      const alt = adiada();
      buscarInteligente.mockImplementation((termo, exceto) =>
        exceto
          ? alt.promessa
          : Promise.resolve({ data: { melhor: WHATSAPP, certeza: 0.9 } })
      );
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');

      expect(cartao(tela)).toBeUndefined();
      expect(itensDaLista(tela)).toHaveLength(0);

      alt.resolver({ data: { melhor: FUNIL, certeza: 0.6 } });
      await flushPromises();

      expect(cartaoDaAlternativa(tela).text()).toContain(FUNIL.titulo);
      expect(itensDaLista(tela).join(' ')).not.toContain(FUNIL.titulo);
      expect(anuncio(tela)).toContain(
        'HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.ANUNCIO_ALTERNATIVA'
      );
    });

    it('passou o teto da alternativa, a tela abre sem ela e a resposta atrasada não entra', async () => {
      buscar.mockResolvedValue({
        data: { resultados: [SENHA, FUNIL, CONTATOS] },
      });
      const alt = adiada();
      buscarInteligente.mockImplementation((termo, exceto) =>
        exceto
          ? alt.promessa
          : Promise.resolve({ data: { melhor: WHATSAPP, certeza: 0.9 } })
      );
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');
      await vi.advanceTimersByTimeAsync(1000);
      await flushPromises();

      expect(cartao(tela)).toBeDefined();
      const antes = itensDaLista(tela);
      expect(antes).toHaveLength(3);

      alt.resolver({ data: { melhor: FUNIL, certeza: 0.9 } });
      await flushPromises();

      expect(cartaoDaAlternativa(tela)).toBeUndefined();
      expect(itensDaLista(tela)).toEqual(antes);
    });

    it('apagar o texto com a alternativa a caminho não deixa nada na tela', async () => {
      buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
      const alt = adiada();
      buscarInteligente.mockImplementation((termo, exceto) =>
        exceto
          ? alt.promessa
          : Promise.resolve({ data: { melhor: WHATSAPP, certeza: 0.9 } })
      );
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');
      await tela.find('input').setValue('');
      alt.resolver({ data: { melhor: FUNIL, certeza: 0.9 } });
      await flushPromises();

      expect(cartaoDaAlternativa(tela)).toBeUndefined();
      expect(cartao(tela)).toBeUndefined();
    });

    it('alternativa de um termo antigo não aparece no novo', async () => {
      buscar.mockResolvedValue({ data: { resultados: [SENHA] } });
      const atrasada = adiada();
      buscarInteligente.mockImplementation((termo, exceto) => {
        if (exceto && termo === 'como conecto meu zap')
          return atrasada.promessa;
        return Promise.resolve({
          data: {
            melhor: exceto ? null : WHATSAPP,
            certeza: exceto ? null : 0.9,
          },
        });
      });
      const tela = montar();
      await digitar(tela, 'como conecto meu zap');
      await digitar(tela, 'trocar senha');
      atrasada.resolver({ data: { melhor: FUNIL, certeza: 0.9 } });
      await flushPromises();

      expect(cartaoDaAlternativa(tela)).toBeUndefined();
    });
  });
});
