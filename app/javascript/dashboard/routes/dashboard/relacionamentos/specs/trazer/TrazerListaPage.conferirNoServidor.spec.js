import { flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  botao,
  continuar,
  erroHttp,
  escolher,
  esperarPor,
  marca,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
// A página "Trazer minha lista" inteira falando com o servidor de mentira
// (#2896): as perguntas, o conserto e o "voltar atrás" de cada linha, a troca
// de coluna e o trazer, com cada recusa dita no lugar da ação.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

const estado = vi.hoisted(() => ({ demo: 'cheio' }));

const empurrar = vi.hoisted(() => vi.fn());

const alertar = vi.hoisted(() => vi.fn());

// O servidor de mentira (fora da demonstração a tela fala com ele, #2896).
const servidor = vi.hoisted(() => ({
  enviar: vi.fn(),
  leitura: vi.fn(),
  responder: vi.fn(),
  consertar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarColuna: vi.fn(),
  trazer: vi.fn(),
  listas: vi.fn(),
  andamento: vi.fn(),
  confirmar: vi.fn(),
}));

// #2897 — a conta destes testes não tem a carteira de seguros: a tela é a das
// listas, sem a pergunta dos seguros.
vi.mock('../../carteira/useContaDeSeguros', async () => {
  const { ref } = await import('vue');
  return { useContaDeSeguros: () => ref(false) };
});

vi.mock('dashboard/api/relacionamentosTrazer', () => ({ default: servidor }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: empurrar, replace: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: alertar }));

vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));

// A fonte de verdade, sem as esperas da demonstração.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerFonte: opcoes =>
      original.trazerFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      }),
  };
});

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'cheio';
  empurrar.mockClear();
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

// #2896, Fatia 2 — perguntas, conserto, deixar de fora, voltar atrás, a
// informação nova e o trazer, com o servidor de mentira.
describe('com o servidor: perguntas, linhas e colunas', () => {
  const COLUNAS = [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Cel', destino: 'telefone' },
    { indice: 2, nome: 'Fone 2', destino: 'telefone', duvidosa: true },
    { indice: 3, nome: 'E-mail', destino: 'email' },
    {
      indice: 6,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    },
  ];
  const PROBLEMAS = [
    {
      linha: 14,
      tipo: 'telefone',
      nome: 'Tadeu Imbirussu',
      valor: '+55 11 9738-0014',
      estado: 'aberto',
    },
    {
      linha: 37,
      tipo: 'email',
      nome: 'Rita Carvalhedo',
      valor: 'rita.carvalhedo.exemplo.com.br',
      estado: 'aberto',
    },
  ];
  const leitura = (extra = {}) => ({
    id: 812,
    situacao: 'pronta',
    arquivo: 'Clientes 2025.csv',
    valores: 'inteiros',
    colunas: COLUNAS,
    perguntas: [{ id: 'clientes' }, { id: 'telefone', coluna: 'Fone 2' }],
    respostas: {},
    resumo: {
      total: 10,
      novas: 6,
      completadas: 2,
      comProblema: 2,
      juntadas: 0,
      entram: 8,
    },
    exemplos: [
      { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: '' },
    ],
    problemas: PROBLEMAS,
    problemas_total: 2,
    pagina: 1,
    por_pagina: 200,
    ...extra,
  });
  const RESPONDIDA = { clientes: 'sim_todas', telefone: 'da_pessoa' };

  beforeEach(() => {
    estado.demo = null;
    Element.prototype.scrollIntoView = vi.fn();
    servidor.listas.mockResolvedValue({ data: [] });
    servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
    servidor.leitura.mockResolvedValue({ data: leitura() });
    servidor.responder.mockResolvedValue({
      data: leitura({ respostas: RESPONDIDA }),
    });
  });

  const enviar = async w => {
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;cel'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'pergunta');
  };
  const ateConferir = async () => {
    const w = await abrir();
    await enviar(w);
    await escolher(w, 'sim_todas');
    await continuar(w);
    await esperarPor(() =>
      expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('telefone')
    );
    await escolher(w, 'da_pessoa');
    await continuar(w);
    await aparece(w, 'conferir');
    return w;
  };
  const abrirOQueVouGuardar = async w => {
    await marca(w, 'o-que-vou-guardar').get('h2 button').trigger('click');
  };
  const SALVAR_GENERICO = 'Não consegui salvar. Tente de novo.';

  it('as perguntas vêm do servidor e as respostas vão para ele na última', async () => {
    const w = await abrir();
    await enviar(w);
    expect(marca(w, 'pergunta').get('h1').text()).toBe(
      'Essas pessoas já são clientes?'
    );
    await escolher(w, 'sim_todas');
    await continuar(w);
    await esperarPor(() =>
      expect(marca(w, 'pergunta').get('h1').text()).toBe(
        'A coluna “Fone 2” é telefone de quem?'
      )
    );
    expect(servidor.responder).not.toHaveBeenCalled();
    await escolher(w, 'da_pessoa');
    await continuar(w);
    await aparece(w, 'conferir');
    expect(servidor.responder).toHaveBeenCalledWith(812, RESPONDIDA);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('o servidor recusa o conserto (422): a frase certa aparece na própria linha, com o foco no campo, sem aviso genérico', async () => {
    const w = await ateConferir();
    servidor.consertar.mockRejectedValueOnce(
      erroHttp(422, { error: 'valor_invalido', motivo: 'invalid_email' })
    );
    const linha = () => w.get('[data-linha="37"]');
    await linha().get('input').setValue('rita@exemplo.com.br');
    await linha().get('form').trigger('submit');
    await esperarPor(() =>
      expect(linha().find('[role="alert"]').exists()).toBe(true)
    );
    expect(linha().get('[role="alert"]').text()).toBe(
      'Este e-mail não parece certo.'
    );
    expect(document.activeElement).toBe(linha().get('input').element);
    expect(alertar).not.toHaveBeenCalled();
    expect(servidor.consertar).toHaveBeenCalledWith(812, 37, {
      valor: 'rita@exemplo.com.br',
    });
    // A outra linha não ganha frase nenhuma.
    expect(w.get('[data-linha="14"]').find('[role="alert"]').exists()).toBe(
      false
    );

    // Consertou de verdade: a linha vira "Pronto" e o botão conta mais uma.
    servidor.consertar.mockResolvedValueOnce({
      data: {
        problema: {
          ...PROBLEMAS[1],
          estado: 'guardado',
          corrigido: 'rita.carvalhedo@exemplo.com.br',
        },
        entram: 9,
      },
    });
    await linha().get('input').setValue('rita.carvalhedo@exemplo.com.br');
    expect(linha().find('[role="alert"]').exists()).toBe(false);
    await linha().get('form').trigger('submit');
    await esperarPor(() =>
      expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 9 pessoas')
    );
    expect(linha().text()).toContain('Pronto');
    expect(servidor.leitura).toHaveBeenCalledTimes(1);
    w.unmount();
  });

  it('deixar de fora e voltar atrás vão ao servidor, sem reler a planilha', async () => {
    const w = await ateConferir();
    servidor.deixarDeFora.mockResolvedValue({
      data: { problema: { ...PROBLEMAS[0], estado: 'deixado' }, entram: 8 },
    });
    servidor.reabrir.mockResolvedValue({
      data: { problema: { ...PROBLEMAS[0], estado: 'aberto' }, entram: 8 },
    });
    const linha = () => w.get('[data-linha="14"]');
    await linha()
      .get('[data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() => expect(linha().text()).toContain('Deixada de fora'));
    expect(servidor.deixarDeFora).toHaveBeenCalledWith(812, 14);
    await linha().get('[data-relacionamentos="voltar-atras"]').trigger('click');
    await esperarPor(() => expect(linha().find('form').exists()).toBe(true));
    expect(servidor.reabrir).toHaveBeenCalledWith(812, 14);
    expect(servidor.leitura).toHaveBeenCalledTimes(1);
    w.unmount();
  });

  it('voltar atrás que falha: a frase fica na própria linha, como alerta, com o foco de volta no "Voltar atrás"', async () => {
    const w = await ateConferir();
    servidor.deixarDeFora.mockResolvedValue({
      data: { problema: { ...PROBLEMAS[0], estado: 'deixado' }, entram: 8 },
    });
    servidor.reabrir.mockRejectedValueOnce(erroHttp(500));
    const linha = () => w.get('[data-linha="14"]');
    const voltarAtras = () =>
      linha().get('[data-relacionamentos="voltar-atras"]');
    await linha()
      .get('[data-relacionamentos="deixar-de-fora"]')
      .trigger('click');
    await esperarPor(() => expect(linha().text()).toContain('Deixada de fora'));
    await voltarAtras().trigger('click');
    await esperarPor(() =>
      expect(linha().find('[role="alert"]').exists()).toBe(true)
    );
    expect(linha().get('[role="alert"]').text()).toBe(
      'Não consegui salvar esta linha. Tente de novo.'
    );
    await esperarPor(() =>
      expect(document.activeElement).toBe(voltarAtras().element)
    );
    // A linha continua de fora, e a outra não ganha frase nenhuma.
    expect(linha().text()).toContain('Deixada de fora');
    expect(w.get('[data-linha="37"]').find('[role="alert"]').exists()).toBe(
      false
    );
    // A linha já diz tudo: sem aviso solto repetindo a frase.
    expect(alertar).not.toHaveBeenCalled();

    // Tentou de novo e deu certo: a frase some e a linha volta a abrir.
    servidor.reabrir.mockResolvedValueOnce({
      data: { problema: { ...PROBLEMAS[0], estado: 'aberto' }, entram: 8 },
    });
    await voltarAtras().trigger('click');
    await esperarPor(() => expect(linha().find('form').exists()).toBe(true));
    expect(linha().find('[role="alert"]').exists()).toBe(false);
    w.unmount();
  });

  it('responder de novo depois de consertar não perde o conserto', async () => {
    const w = await ateConferir();
    servidor.consertar.mockResolvedValueOnce({
      data: {
        problema: {
          ...PROBLEMAS[1],
          estado: 'guardado',
          corrigido: 'rita.carvalhedo@exemplo.com.br',
        },
        entram: 9,
      },
    });
    await w
      .get('[data-linha="37"] input')
      .setValue('rita.carvalhedo@exemplo.com.br');
    await w.get('[data-linha="37"] form').trigger('submit');
    await esperarPor(() =>
      expect(w.get('[data-linha="37"]').text()).toContain('Pronto')
    );
    // Volta à última pergunta e responde outra coisa: o servidor devolve a
    // leitura inteira, com o conserto que ele guardou.
    servidor.responder.mockResolvedValueOnce({
      data: leitura({
        respostas: { clientes: 'sim_todas', telefone: 'da_empresa' },
        resumo: {
          total: 10,
          novas: 6,
          completadas: 2,
          comProblema: 2,
          juntadas: 0,
          entram: 9,
        },
        problemas: [
          PROBLEMAS[0],
          {
            ...PROBLEMAS[1],
            estado: 'guardado',
            corrigido: 'rita.carvalhedo@exemplo.com.br',
          },
        ],
      }),
    });
    await botao(marca(w, 'conferir'), 'Voltar').trigger('click');
    await aparece(w, 'pergunta');
    await escolher(w, 'da_empresa');
    await continuar(w);
    await aparece(w, 'conferir');
    expect(servidor.responder).toHaveBeenLastCalledWith(812, {
      clientes: 'sim_todas',
      telefone: 'da_empresa',
    });
    expect(w.get('[data-linha="37"]').text()).toContain('Pronto');
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 9 pessoas');
    w.unmount();
  });

  it('tirar a última coluna de contato: a frase própria na linha da coluna, não o "não consegui salvar"', async () => {
    const w = await ateConferir();
    servidor.trocarColuna.mockRejectedValueOnce(
      erroHttp(422, { error: 'sem_contato' })
    );
    await abrirOQueVouGuardar(w);
    const coluna = w.get('[data-coluna="E-mail"]');
    await botao(coluna, 'Mudar').trigger('click');
    await flushPromises();
    await coluna
      .get('[role="option"][data-value="nao_guardar"]')
      .trigger('click');
    await esperarPor(() => expect(alertar).toHaveBeenCalled());
    expect(servidor.trocarColuna).toHaveBeenCalledWith(812, 3, {
      destino: 'nao_guardar',
    });
    const SEM_COLUNA =
      'Não mudei esta coluna: a lista precisa de pelo menos uma coluna de telefone ou de e-mail.';
    const recusa = w.get(
      '[data-coluna="E-mail"] [data-relacionamentos="recusa-da-coluna"]'
    );
    expect(recusa.text()).toBe(SEM_COLUNA);
    expect(recusa.attributes('role')).toBe('alert');
    expect(alertar).toHaveBeenCalledWith(SEM_COLUNA);
    expect(alertar).not.toHaveBeenCalledWith(SALVAR_GENERICO);
    w.unmount();
  });

  it('informação nova: o nome do campo e o "Para que serve?" vão com o destino', async () => {
    const w = await ateConferir();
    const campo = {
      nome: 'Situação',
      para_que_serve: 'mês em que o seguro vence',
    };
    servidor.trocarColuna.mockResolvedValueOnce({
      data: {
        id: 812,
        situacao: 'pronta',
        colunas: COLUNAS.map(coluna =>
          coluna.indice === 6 ? { ...coluna, campo } : coluna
        ),
      },
    });
    await abrirOQueVouGuardar(w);
    const coluna = () => w.get('[data-coluna="Situação"]');
    expect(coluna().get('input[data-campo="nome"]').element.value).toBe(
      'Situação'
    );
    await coluna()
      .get('input[data-campo="para-que-serve"]')
      .setValue('mês em que o seguro vence');
    await coluna()
      .get('[data-relacionamentos="campo-da-informacao"]')
      .trigger('submit');
    await esperarPor(() =>
      expect(coluna().get('[role="status"]').text()).toBe('Salvo')
    );
    expect(servidor.trocarColuna).toHaveBeenCalledWith(812, 6, {
      destino: 'informacao',
      ...campo,
    });
    expect(
      coluna().get('input[data-campo="para-que-serve"]').element.value
    ).toBe('mês em que o seguro vence');
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('Trazer fecha a conferência da leitura no servidor', async () => {
    const w = await ateConferir();
    servidor.trazer.mockResolvedValue({ data: { trazidaId: 812 } });
    servidor.andamento.mockResolvedValue({
      data: {
        porcentagem: 100,
        situacao: 'pronto',
        total: 8,
        novas: 6,
        completadas: 2,
      },
    });
    await botao(w, 'Trazer 8 pessoas').trigger('click');
    await aparece(w, 'pronto');
    expect(servidor.trazer).toHaveBeenCalledWith(812);
    expect(servidor.confirmar).not.toHaveBeenCalled();
    w.unmount();
  });
});
