import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import {
  PERGUNTAS,
  erroDeNome,
  fonteDeMentira,
  lida,
  montarTela,
  noConferir,
  problema,
} from './apoioDaTela';

// #2896, Fatia 2 — a escrita que o servidor recusa (ou que falha) nunca é dita
// só num aviso que some: a frase fica fixa, como alerta, no lugar onde a pessoa
// agiu (a linha da coluna, a pergunta, o cartão da linha), e o foco volta ao
// controle. O aviso solto pode vir junto, como reforço.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const SEM_COLUNA_DE_CONTATO =
  'Não mudei esta coluna: a lista precisa de pelo menos uma coluna de telefone ou de e-mail.';
const CHAVE_SEM_COLUNA = 'RELACIONAMENTOS_TRAZER.ERROS.SEM_COLUNA_DE_CONTATO';
const CHAVE_GUARDAR = 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR';
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('o estado guarda a recusa no lugar da ação', () => {
  it.each([
    ['TROCA_SEM_CONTATO', {}, CHAVE_SEM_COLUNA],
    ['SEM_EMPRESA', {}, 'RELACIONAMENTOS_TRAZER.ERROS.SEM_EMPRESA'],
    [
      'VALOR_INVALIDO',
      { motivo: 'muito_longo' },
      'RELACIONAMENTOS_TRAZER.ERROS.MUITO_LONGO',
    ],
    ['Error', {}, CHAVE_GUARDAR],
  ])(
    'a troca de coluna que falha (%s) fica com a coluna',
    async (nome, extra, chave) => {
      const { tela, avisar } = await noConferir(lida(), {
        trocarDestino: vi.fn().mockRejectedValue(erroDeNome(nome, extra)),
      });
      expect(await tela.trocarDestino(1, 'nao_guardar')).toBe(false);
      expect(tela.recusaDaColuna.value).toEqual({ coluna: 1, chave });
      expect(tela.recusaDaPergunta.value).toBeNull();
      // O aviso solto é só reforço: a mesma frase.
      expect(avisar).toHaveBeenCalledWith(chave);
    }
  );

  it('a recusa da coluna some na escrita seguinte', async () => {
    const { tela } = await noConferir(lida(), {
      trocarDestino: vi
        .fn()
        .mockRejectedValueOnce(erroDeNome('TROCA_SEM_CONTATO'))
        .mockResolvedValueOnce(lida()),
    });
    await tela.trocarDestino(1, 'nao_guardar');
    expect(tela.recusaDaColuna.value).not.toBeNull();
    await tela.trocarDestino(6, 'cidade');
    expect(tela.recusaDaColuna.value).toBeNull();
  });

  it('a mesma recusa duas vezes é dita duas vezes (um objeto novo a cada vez)', async () => {
    const { tela } = await noConferir(lida(), {
      trocarDestino: vi.fn().mockRejectedValue(erroDeNome('TROCA_SEM_CONTATO')),
    });
    await tela.trocarDestino(1, 'nao_guardar');
    const primeira = tela.recusaDaColuna.value;
    await tela.trocarDestino(1, 'nao_guardar');
    expect(tela.recusaDaColuna.value).toEqual(primeira);
    expect(tela.recusaDaColuna.value).not.toBe(primeira);
  });

  it('a resposta que o servidor recusa fica com a pergunta', async () => {
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(lida({ perguntas: [PERGUNTAS[1]] })),
      responder: vi.fn().mockRejectedValue(erroDeNome('TROCA_SEM_CONTATO')),
    });
    const { tela, avisar } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('telefone', 'nao_usar');
    await tela.continuar();
    expect(tela.recusaDaPergunta.value).toEqual({ chave: CHAVE_SEM_COLUNA });
    expect(tela.recusaDaColuna.value).toBeNull();
    expect(avisar).toHaveBeenCalledWith(CHAVE_SEM_COLUNA);
  });

  it.each([
    ['muda a resposta', tela => tela.responder('telefone', 'da_pessoa')],
    ['volta', tela => tela.voltar()],
  ])('a recusa da pergunta some quando a pessoa %s', async (_, agir) => {
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(lida({ perguntas: [PERGUNTAS[1]] })),
      responder: vi.fn().mockRejectedValue(erroDeNome('TROCA_SEM_CONTATO')),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('telefone', 'nao_usar');
    await tela.continuar();
    expect(tela.recusaDaPergunta.value).not.toBeNull();
    agir(tela);
    expect(tela.recusaDaPergunta.value).toBeNull();
  });

  it.each([
    ['consertar', tela => tela.guardar(14, 'x')],
    ['deixarDeFora', tela => tela.deixarDeFora(14)],
    ['reabrir', tela => tela.reabrir(14)],
  ])(
    'a falha sem nome em %s fica só com a linha (sem aviso solto), com o motivo de quem não salvou',
    async (metodo, agir) => {
      const { tela, avisar } = await noConferir(lida(), {
        [metodo]: vi.fn().mockRejectedValue(new Error('caiu')),
      });
      expect(await agir(tela)).toBe(false);
      expect(tela.recusaDoConserto.value).toEqual({
        linha: 14,
        motivo: 'nao_salvou',
      });
      expect(avisar).not.toHaveBeenCalled();
    }
  );

  it('o valor que o servidor recusa fica só na linha, sem aviso solto', async () => {
    const { tela, avisar } = await noConferir(lida(), {
      consertar: vi
        .fn()
        .mockRejectedValue(
          erroDeNome('VALOR_INVALIDO', { motivo: 'invalid_email' })
        ),
    });
    await tela.guardar(14, 'x');
    expect(tela.recusaDoConserto.value).toEqual({
      linha: 14,
      motivo: 'invalid_email',
    });
    expect(avisar).not.toHaveBeenCalled();
  });
});

describe('a linha da coluna diz a recusa ali mesmo', () => {
  const CEL = { indice: 1, nome: 'Cel', destino: 'telefone' };
  const montar = (props = {}) =>
    mount(LinhaDeColuna, {
      attachTo: document.body,
      props: { coluna: CEL, ...props },
    });

  it('sem recusa não há alerta', () => {
    expect(marca(montar(), 'recusa-da-coluna').exists()).toBe(false);
  });

  it('com recusa: a frase fixa como alerta e o foco no "Mudar"', async () => {
    const w = montar();
    await w.setProps({ recusa: { coluna: 1, chave: CHAVE_SEM_COLUNA } });
    await flushPromises();
    const alerta = marca(w, 'recusa-da-coluna');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(SEM_COLUNA_DE_CONTATO);
    expect(document.activeElement).toBe(marca(w, 'trocar-coluna').element);
  });

  it('na informação nova, o foco volta ao nome dela', async () => {
    const w = montar({
      coluna: {
        indice: 6,
        nome: 'Situação',
        destino: 'informacao',
        campo: { nome: 'Situação', para_que_serve: '' },
      },
    });
    await w.setProps({
      recusa: { coluna: 6, chave: 'RELACIONAMENTOS_TRAZER.ERROS.MUITO_LONGO' },
    });
    await flushPromises();
    expect(marca(w, 'recusa-da-coluna').text()).toBe(
      'Este texto é longo demais. Encurte e tente de novo.'
    );
    expect(document.activeElement).toBe(
      w.get('input[data-campo="nome"]').element
    );
  });

  it('"O que vou guardar" entrega a recusa só à coluna dela', async () => {
    const w = mount(OQueVouGuardar, {
      attachTo: document.body,
      props: {
        colunas: lida().colunas,
        recusa: { coluna: 1, chave: CHAVE_SEM_COLUNA },
      },
    });
    await flushPromises();
    const alertas = w.findAll('[data-relacionamentos="recusa-da-coluna"]');
    expect(alertas).toHaveLength(1);
    expect(w.get('[data-coluna="Cel"]').text()).toContain(
      SEM_COLUNA_DE_CONTATO
    );
  });
});

describe('a pergunta diz a recusa ali mesmo', () => {
  const montar = (props = {}) =>
    mount(PerguntaDaVez, {
      attachTo: document.body,
      props: {
        pergunta: PERGUNTAS[1],
        respostas: { telefone: 'nao_usar' },
        podeContinuar: true,
        ...props,
      },
    });

  it('com recusa: a frase fixa como alerta e o foco nas respostas', async () => {
    const w = montar();
    expect(marca(w, 'erro-da-pergunta').exists()).toBe(false);
    await w.setProps({ recusa: { chave: CHAVE_SEM_COLUNA } });
    await flushPromises();
    const alerta = marca(w, 'erro-da-pergunta');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(SEM_COLUNA_DE_CONTATO);
    expect(document.activeElement.getAttribute('data-resposta')).toBe(
      'nao_usar'
    );
  });

  it('a frase some quando a recusa deixa de valer', async () => {
    const w = montar({ recusa: { chave: CHAVE_SEM_COLUNA } });
    await flushPromises();
    expect(marca(w, 'erro-da-pergunta').exists()).toBe(true);
    await w.setProps({ recusa: null });
    expect(marca(w, 'erro-da-pergunta').exists()).toBe(false);
  });
});

describe('o cartão da linha diz a falha que não é do valor', () => {
  it('que não conseguiu salvar, como alerta, sem culpar o campo', async () => {
    const w = mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: {
        problemas: [problema(14), problema(37, { tipo: 'duplicada' })],
        recusa: { linha: 14, motivo: 'nao_salvou' },
      },
    });
    await flushPromises();
    expect(w.get('[data-linha="14"] [role="alert"]').text()).toBe(
      'Não consegui salvar esta linha. Tente de novo.'
    );
    expect(w.findAll('[role="alert"]')).toHaveLength(1);
  });
});
