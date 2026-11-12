import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  MARCADOR,
  PERGUNTAS,
  emVoo,
  erroDeNome,
  fonteDeMentira,
  lida,
} from './apoioDaTela';

// #2896, Fatia 2 — a página "Trazer minha lista" e a leitura em aberto: o id
// dela fica na rota (`?leitura=`), para a página recarregada continuar de onde
// estava, e a página mostra os estados da leitura que volta do servidor fora de
// hora (lendo de novo, a espera que falhou, a lista que mudou, a mudança que o
// servidor desfez). A fonte aqui é de mentira: o que ela faz com o servidor está
// em retomada.spec.js e releitura.spec.js.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const palco = vi.hoisted(() => ({
  demo: null,
  fonte: null,
  rota: { query: {} },
}));
const substituir = vi.hoisted(() => vi.fn());

vi.mock('vue-router', () => ({
  useRoute: () => palco.rota,
  useRouter: () => ({ push: vi.fn(), replace: substituir }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => palco.demo,
}));
vi.mock('../../fonte/trazerFonte', async importOriginal => ({
  ...(await importOriginal()),
  trazerFonte: () => palco.fonte,
}));

const JA_TRAZIDA = 'Esta lista já foi trazida. Veja abaixo.';
const DEMOROU = 'Ainda não terminei de ler sua planilha.';
const SEM_NINGUEM =
  'Com essa mudança não sobrou ninguém com telefone ou e-mail. Envie a planilha de novo.';
const PAROU =
  'Ainda não terminei de ler sua planilha de novo. O que você mudou já está salvo.';
const VENCIDA =
  'Esta planilha foi enviada há mais de 7 dias e já foi apagada daqui. Envie a planilha de novo.';
const PENDENTE = () => erroDeNome('LEITURA_PENDENTE', { leituraId: 'l1' });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);

const fonteDaPagina = (extra = {}) =>
  fonteDeMentira({ historico: vi.fn().mockResolvedValue([]), ...extra });

const abrir = async (extra = {}) => {
  palco.fonte = fonteDaPagina(extra);
  const w = mount(TrazerListaPage, {
    attachTo: document.body,
    global: {
      stubs: { RouterLink: RouterLinkStub, Dialog: { template: '<div />' } },
    },
  });
  await flushPromises();
  return w;
};

const enviar = async w => {
  w.findComponent(TelaEnviar).vm.$emit('arquivo', { name: 'a.csv' });
  await flushPromises();
};

// Abre a página, envia a planilha e chega ao Conferir.
const noConferir = async (extra = {}) => {
  const w = await abrir(extra);
  await enviar(w);
  expect(marca(w, 'conferir').exists()).toBe(true);
  return w;
};

const doConferir = async (w, evento, ...dados) => {
  w.findComponent(TelaConferir).vm.$emit(evento, ...dados);
  await flushPromises();
};

beforeEach(() => {
  palco.demo = null;
  palco.rota.query = {};
  substituir.mockReset();
  // Como o roteador de verdade: a rota passa a ter a query pedida.
  substituir.mockImplementation(({ query }) => {
    palco.rota.query = query;
  });
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('a leitura em aberto fica na rota', () => {
  it('depois do envio, a rota guarda o id da leitura', async () => {
    await noConferir();
    expect(substituir).toHaveBeenCalledTimes(1);
    expect(substituir).toHaveBeenCalledWith({ query: { leitura: 'l1' } });
  });

  it('o que a rota já tinha continua lá', async () => {
    palco.rota.query = { aba: 'x' };
    await noConferir();
    expect(substituir).toHaveBeenCalledWith({
      query: { aba: 'x', leitura: 'l1' },
    });
  });

  it('em demonstração a rota não muda', async () => {
    palco.demo = 'cheio';
    await noConferir();
    expect(substituir).not.toHaveBeenCalled();
  });

  it('ao trazer, a leitura sai da rota', async () => {
    const w = await noConferir();
    await marca(w, 'trazer-confirmar').trigger('click');
    await flushPromises();
    expect(palco.fonte.trazer).toHaveBeenCalledWith('l1');
    expect(palco.rota.query.leitura).toBeUndefined();
  });

  it('ao voltar para o Enviar, também', async () => {
    const w = await noConferir();
    await botao(w, 'Voltar').trigger('click');
    await flushPromises();
    expect(marca(w, 'enviar').exists()).toBe(true);
    expect(palco.rota.query.leitura).toBeUndefined();
  });
});

describe('a página aberta com a leitura na rota', () => {
  beforeEach(() => {
    palco.rota.query = { leitura: 'l1' };
  });

  it('pergunta pela leitura, sem enviar arquivo, e cai no Conferir', async () => {
    const w = await abrir({ retomar: vi.fn().mockResolvedValue(lida()) });
    expect(palco.fonte.retomar).toHaveBeenCalledWith('l1');
    expect(palco.fonte.ler).not.toHaveBeenCalled();
    expect(marca(w, 'conferir').exists()).toBe(true);
    // A rota já diz a leitura: não há o que trocar.
    expect(substituir).not.toHaveBeenCalled();
  });

  it('com uma pergunta sem resposta, cai nela', async () => {
    const w = await abrir({
      retomar: vi.fn().mockResolvedValue(
        lida({
          perguntas: PERGUNTAS,
          respostas: { clientes: 'sim_todas' },
        })
      ),
    });
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('telefone');
  });

  it('a leitura que já foi trazida: diz isso, mostra o histórico de novo e limpa a rota', async () => {
    const w = await abrir({
      retomar: vi.fn().mockRejectedValue(erroDeNome('LEITURA_NAO_ENCONTRADA')),
    });
    const alerta = marca(w, 'ja-trazida');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(JA_TRAZIDA);
    expect(marca(w, 'enviar').exists()).toBe(true);
    expect(palco.fonte.historico).toHaveBeenCalledTimes(2);
    expect(palco.rota.query.leitura).toBeUndefined();
  });

  it('a conferência vencida: diz a frase fixa, sem "Tentar de novo", e limpa a rota', async () => {
    const w = await abrir({
      retomar: vi.fn().mockRejectedValue(erroDeNome('CONFERENCIA_VENCIDA')),
    });
    const alerta = marca(w, 'vencida');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(VENCIDA);
    expect(marca(w, 'enviar').exists()).toBe(true);
    expect(marca(w, 'soltar-arquivo').exists()).toBe(true);
    expect(botao(w, 'Tentar de novo')).toBeUndefined();
    expect(palco.rota.query.leitura).toBeUndefined();
  });

  it('a leitura que o servidor ainda não terminou: "Tentar de novo" só pergunta de novo', async () => {
    const w = await abrir({
      retomar: vi
        .fn()
        .mockRejectedValueOnce(PENDENTE())
        .mockResolvedValueOnce(lida()),
    });
    expect(marca(w, 'erro').text()).toContain(DEMOROU);
    expect(palco.rota.query.leitura).toBe('l1');
    await botao(w, 'Tentar de novo').trigger('click');
    await flushPromises();
    expect(palco.fonte.retomar).toHaveBeenCalledTimes(2);
    expect(palco.fonte.ler).not.toHaveBeenCalled();
    expect(marca(w, 'conferir').exists()).toBe(true);
  });

  it('em demonstração o parâmetro não vale', async () => {
    palco.demo = 'cheio';
    const w = await abrir();
    expect(palco.fonte.retomar).not.toHaveBeenCalled();
    expect(marca(w, 'enviar').exists()).toBe(true);
  });
});

describe('a planilha lida de novo depois de uma mudança', () => {
  it('enquanto lê, a tela diz isso; quando termina, a frase some', async () => {
    const leitura = emVoo();
    const w = await noConferir({
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi.fn(() => leitura.promessa),
    });
    await doConferir(w, 'trocar', 1, 'email');
    expect(marca(w, 'relendo').text()).toBe('Lendo sua planilha de novo…');
    leitura.resolver(lida());
    await flushPromises();
    expect(marca(w, 'relendo').text()).toBe('');
  });

  it('a espera que falha tem estado próprio; "Tentar de novo" só pergunta de novo', async () => {
    const w = await noConferir({
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi
        .fn()
        .mockRejectedValueOnce(PENDENTE())
        .mockResolvedValueOnce(lida()),
    });
    await doConferir(w, 'trocar', 1, 'email');
    expect(marca(w, 'releitura-parada').text()).toContain(PAROU);
    expect(marca(w, 'conferir').exists()).toBe(false);
    // A leitura continua em aberto: a rota não a perde.
    expect(palco.rota.query.leitura).toBe('l1');
    await botao(w, 'Tentar de novo').trigger('click');
    await flushPromises();
    expect(palco.fonte.trocarDestino).toHaveBeenCalledTimes(1);
    expect(palco.fonte.retomar).toHaveBeenCalledTimes(2);
    expect(marca(w, 'releitura-parada').exists()).toBe(false);
    expect(marca(w, 'conferir').exists()).toBe(true);
  });

  it('não sobrou ninguém: volta ao Enviar com a frase fixa', async () => {
    const w = await noConferir({
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi.fn().mockRejectedValue(erroDeNome('PLANILHA_SEM_CONTATO')),
    });
    await doConferir(w, 'trocar', 1, 'nao_guardar');
    expect(marca(w, 'enviar').exists()).toBe(true);
    const alerta = marca(w, 'sem-ninguem');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(SEM_NINGUEM);
  });

  it('a conferência venceu no meio do Conferir: volta ao Enviar com a frase fixa e a rota fica sem a leitura', async () => {
    const w = await noConferir({
      deixarDeFora: vi
        .fn()
        .mockRejectedValue(erroDeNome('CONFERENCIA_VENCIDA')),
    });
    expect(palco.rota.query.leitura).toBe('l1');
    await doConferir(w, 'deixarDeFora', 14);
    expect(marca(w, 'conferir').exists()).toBe(false);
    expect(marca(w, 'enviar').exists()).toBe(true);
    const alerta = marca(w, 'vencida');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(VENCIDA);
    expect(palco.rota.query.leitura).toBeUndefined();
  });

  it('a lista que mudou por fora é lida de novo sozinha, e a tela diz', async () => {
    const w = await noConferir({
      deixarDeFora: vi.fn().mockRejectedValue(erroDeNome('TELA_DESATUALIZADA')),
      retomar: vi.fn().mockResolvedValue(lida()),
    });
    expect(marca(w, 'lista-mudou').exists()).toBe(false);
    await doConferir(w, 'deixarDeFora', 14);
    expect(palco.fonte.retomar).toHaveBeenCalledWith('l1');
    const alerta = marca(w, 'lista-mudou');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(
      'Esta lista mudou enquanto você conferia. Mostrei como está agora.'
    );
    expect(w.text()).not.toContain('atualize a página');
  });
});

describe('a mudança que o servidor desfez', () => {
  const DESFEITA =
    'Não fiz essa mudança: com ela não sobraria ninguém com telefone ou e-mail. Deixei como estava.';

  it('é dita no topo do Conferir, antes do resto', async () => {
    const w = await noConferir({
      ler: vi.fn().mockResolvedValue(lida({ aviso: 'mudanca_desfeita' })),
    });
    const alerta = marca(w, 'mudanca-desfeita');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(DESFEITA);
    const posicao = nome => w.html().indexOf(`data-relacionamentos="${nome}"`);
    expect(posicao('mudanca-desfeita')).toBeLessThan(posicao('conferir'));
  });

  it('é dita também na pergunta a que a pessoa voltou', async () => {
    const w = await abrir({
      ler: vi.fn().mockResolvedValue(
        lida({
          aviso: 'mudanca_desfeita',
          perguntas: [PERGUNTAS[1]],
        })
      ),
    });
    await enviar(w);
    expect(marca(w, 'pergunta').exists()).toBe(true);
    expect(marca(w, 'mudanca-desfeita').text()).toBe(DESFEITA);
  });

  it('sem a chave, nada aparece', async () => {
    const w = await noConferir();
    expect(marca(w, 'mudanca-desfeita').exists()).toBe(false);
  });
});

describe('o Enviar diz por que a leitura não está na tela', () => {
  const montar = erro =>
    mount(TelaEnviar, { attachTo: document.body, props: { erro } });

  it('o servidor ainda não terminou: a frase e o "Tentar de novo"', async () => {
    const w = montar(ERROS.DEMOROU);
    expect(marca(w, 'erro').text()).toContain(DEMOROU);
    await botao(w, 'Tentar de novo').trigger('click');
    expect(w.emitted('tentar')).toHaveLength(1);
  });

  it.each([
    [ERROS.SEM_NINGUEM, 'sem-ninguem', SEM_NINGUEM],
    [ERROS.JA_TRAZIDA, 'ja-trazida', JA_TRAZIDA],
    [ERROS.VENCIDA, 'vencida', VENCIDA],
  ])(
    '%s: a frase fixa como alerta, sem botão de tentar',
    (erro, nome, frase) => {
      const w = montar(erro);
      const alerta = marca(w, nome);
      expect(alerta.attributes('role')).toBe('alert');
      expect(alerta.text()).toBe(frase);
      expect(botao(w, 'Tentar de novo')).toBeUndefined();
    }
  );

  it('sem erro, nenhuma das frases aparece', () => {
    const w = montar(ERROS.NENHUM);
    expect(w.findAll('[role="alert"]')).toHaveLength(0);
  });
});
