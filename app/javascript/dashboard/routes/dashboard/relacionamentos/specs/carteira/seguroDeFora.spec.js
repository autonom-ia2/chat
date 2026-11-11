import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { useRoute } from 'vue-router';
import GavetaDeFora from '../../components/carteira/GavetaDeFora.vue';
import PainelDeSeguros from '../../components/carteira/PainelDeSeguros.vue';
import FichaDaPessoaPage from '../../pages/FichaDaPessoaPage.vue';
import { usarDemo } from '../../fonte/modoDemo';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { assentar, carregarDemonstracao, daCarteira, textoDe } from './apoio';

// "Guardar seguro de outra corretora" (#2897, Tela 20): a gaveta que abre do
// painel da conversa e do bloco Seguros da ficha, com a carteira fictícia e o
// texto em pt_BR.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
// As fontes de demonstração sem o atraso de 300 ms.
const semAtraso = vi.hoisted(() => nome => async importOriginal => {
  const real = await importOriginal();
  return { ...real, [nome]: opcoes => real[nome]({ ...opcoes, atraso: 0 }) };
});
vi.mock('../../fonte/fichaFonte', semAtraso('fichaFonte'));
vi.mock('../../fonte/carteiraFonte', semAtraso('carteiraFonte'));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const SEM_SEGURO = 27;
const rota = useRoute();
const noEndereco = busca => window.history.replaceState({}, '', `/${busca}`);

let aberta;
const montar = async pagina => {
  aberta = mount(pagina, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  await assentar();
  return aberta;
};
// O painel mostra a pessoa de exemplo das jornadas (Fábio, com três seguros).
const abrirPainel = async (busca = '') => {
  usarDemo({ demo: 'cheio' });
  noEndereco(busca);
  return montar(PainelDeSeguros);
};
const abrirGaveta = async (busca = '') => {
  const w = await abrirPainel(busca);
  await w.get(daCarteira('painel-guardar-de-fora')).trigger('click');
  await assentar();
  return w;
};
const arquivo = (w, nome) =>
  w.findAll(daCarteira('de-fora-arquivo')).find(botao => botao.text() === nome);
const escolher = async (w, nome) => {
  await arquivo(w, nome).trigger('click');
  await assentar();
};
const responder = async (w, texto) => {
  await w
    .findAll(`${daCarteira('de-fora-quer')} [role="radio"]`)
    .find(cartao => cartao.text() === texto)
    .trigger('click');
};
const guardar = async w => {
  await w.get(daCarteira('guardar-lembrete')).trigger('click');
  await assentar();
};
const emFoco = () => document.activeElement;

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
  usarDemo({ demo: 'desligado' });
  noEndereco('');
  vi.clearAllMocks();
});

describe('Tela 20: guardar seguro de outra corretora, pelo painel da conversa', () => {
  it('abre a gaveta perguntando qual arquivo é o seguro, sem falar em custo', async () => {
    const w = await abrirGaveta();

    const gaveta = w.get('[role="dialog"]');
    expect(gaveta.get('h2').text()).toBe('Seguro de outra corretora');
    expect(gaveta.get('h3').text()).toBe('Qual arquivo é o seguro?');
    expect(
      w.findAll(daCarteira('de-fora-arquivo')).map(botao => botao.text())
    ).toEqual([
      'apolice-auto.pdf',
      'foto-da-apolice.jpg',
      'foto-do-carro.jpg',
      'apolice-sem-data.pdf',
    ]);
    expect(gaveta.text()).toContain('Ou arraste o arquivo aqui');
    expect(gaveta.text()).not.toContain('R$');
    expect(gaveta.text()).not.toContain('custa');
    expect(w.find(daCarteira('guardar-lembrete')).exists()).toBe(false);
  });

  it('mostra o que leu e pergunta se a pessoa quer o lembrete', async () => {
    const w = await abrirGaveta();
    await escolher(w, 'apolice-auto.pdf');

    const lido = w.get(daCarteira('de-fora-lido'));
    expect(lido.get('h3').text()).toBe('O que li');
    expect(lido.text()).toContain('Tipo de seguro');
    expect(lido.text()).toContain('Auto');
    const [seguradora, termina] = lido.findAll('input');
    expect(seguradora.element.value).toBe('Seguradora Aurora');
    expect(termina.attributes('type')).toBe('date');
    expect(termina.element.value).not.toBe('');
    expect(w.get(`${daCarteira('de-fora-quer')} h3`).text()).toBe(
      'Fábio quer que você lembre antes de vencer?'
    );
    expect(
      w
        .findAll(`${daCarteira('de-fora-quer')} [role="radio"]`)
        .map(cartao => cartao.text())
    ).toEqual(['Sim, quer', 'Ainda não perguntei']);
  });

  it('"Guardar lembrete" fica ligado: sem a resposta, diz o que falta e leva o foco', async () => {
    const w = await abrirGaveta();
    await escolher(w, 'apolice-auto.pdf');
    const botao = w.get(daCarteira('guardar-lembrete'));
    expect(botao.attributes('disabled')).toBeUndefined();

    await guardar(w);

    const quer = w.get(daCarteira('de-fora-quer'));
    const aviso = quer.get('[role="alert"]');
    expect(aviso.text()).toBe('Diga se Fábio quer o lembrete.');
    const grupo = quer.get('[role="radiogroup"]');
    expect(grupo.attributes('aria-invalid')).toBe('true');
    expect(grupo.attributes('aria-describedby')).toBe(aviso.attributes('id'));
    expect(emFoco()).toBe(quer.get('[role="radio"]').element);
    expect(w.find('[role="dialog"]').exists()).toBe(true);

    await responder(w, 'Sim, quer');
    expect(quer.find('[role="alert"]').exists()).toBe(false);
  });

  it('guarda, fecha a gaveta, avisa quando vai chamar e deixa desfazer', async () => {
    const w = await abrirGaveta();
    expect(w.findAll(daCarteira('painel-seguro'))).toHaveLength(3);
    await escolher(w, 'apolice-auto.pdf');
    await w
      .get(`${daCarteira('de-fora-lido')} input[type="date"]`)
      .setValue('2027-02-20');
    await responder(w, 'Sim, quer');

    await guardar(w);

    expect(w.find('[role="dialog"]').exists()).toBe(false);
    const aviso = w.get(daCarteira('aviso-vivo'));
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toContain(
      'Lembrete guardado. Vamos chamar Fábio em 22/12.'
    );
    const linhas = w.findAll(daCarteira('painel-seguro'));
    expect(linhas).toHaveLength(4);
    expect(
      linhas.some(linha => linha.text().includes('Em outra corretora'))
    ).toBe(true);

    await w.get(daCarteira('desfazer')).trigger('click');
    await assentar();
    expect(w.get(daCarteira('aviso-vivo')).text()).toBe('Lembrete desfeito.');
    expect(w.findAll(daCarteira('painel-seguro'))).toHaveLength(3);
  });

  it('"Ainda não perguntei" troca o botão por "Perguntar na conversa"', async () => {
    const w = await abrirGaveta();
    await escolher(w, 'apolice-auto.pdf');

    await responder(w, 'Ainda não perguntei');
    expect(w.find(daCarteira('guardar-lembrete')).exists()).toBe(false);
    await w.get(daCarteira('de-fora-perguntar')).trigger('click');
    await assentar();

    expect(useAlert).toHaveBeenLastCalledWith(
      'Pergunta pronta na caixa de mensagem: “Quer que eu te lembre antes do seu seguro vencer? Assim você compara com calma.”'
    );
    expect(w.find('[role="dialog"]').exists()).toBe(false);
    expect(w.findAll(daCarteira('painel-seguro'))).toHaveLength(3);
  });

  it('arquivo que não serve: diz por quê e continua pedindo o arquivo', async () => {
    const w = await abrirGaveta();

    await escolher(w, 'foto-do-carro.jpg');
    expect(w.get(daCarteira('de-fora-erro')).text()).toBe(
      'Este arquivo não parece um seguro. Escolha outro.'
    );
    await escolher(w, 'foto-da-apolice.jpg');
    expect(w.get(daCarteira('de-fora-erro')).text()).toBe(
      'A foto está escura demais. Peça outra com mais luz.'
    );
    expect(w.findAll(daCarteira('de-fora-arquivo'))).toHaveLength(4);
  });

  it('o que a leitura não achou fica vazio; guardar sem a data pede a data', async () => {
    const w = await abrirGaveta();
    await escolher(w, 'apolice-sem-data.pdf');

    const termina = w.get(`${daCarteira('de-fora-lido')} input[type="date"]`);
    expect(termina.element.value).toBe('');
    expect(w.get(daCarteira('de-fora-nao-achei')).text()).toBe(
      'Não achei. Escreva aqui.'
    );

    await responder(w, 'Sim, quer');
    await guardar(w);
    const aviso = w.get(`${daCarteira('de-fora-lido')} [role="alert"]`);
    expect(aviso.text()).toBe('Diga quando o seguro termina.');
    expect(termina.attributes('aria-invalid')).toBe('true');
    expect(termina.attributes('aria-describedby')).toBe(aviso.attributes('id'));
    expect(emFoco()).toBe(termina.element);
  });

  it('Esc fecha a gaveta e o foco volta para o link que a abriu', async () => {
    const w = await abrirPainel();
    const link = w.get(daCarteira('painel-guardar-de-fora'));
    // No navegador o clique já põe o foco no botão; no teste, não.
    link.element.focus();
    await link.trigger('click');
    await assentar();
    expect(emFoco()).not.toBe(link.element);

    await w.get('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    await assentar();

    expect(w.find('[role="dialog"]').exists()).toBe(false);
    expect(emFoco()).toBe(link.element);
  });

  it('quem não tem seguro com a corretora também pode guardar o de fora', async () => {
    const w = await abrirGaveta('?demo-carteira=vazio');

    expect(w.get(daCarteira('painel-vazio')).text()).toBe(
      'Nenhum seguro com você.'
    );
    expect(w.findAll(daCarteira('de-fora-arquivo'))).toHaveLength(4);
  });
});

describe('Tela 20: os estados da gaveta', () => {
  const abrirCom = async fonte => {
    aberta = mount(GavetaDeFora, {
      attachTo: document.body,
      props: { aberta: false, pessoaId: 23, fonte },
      global: { stubs: { transition: true } },
    });
    await aberta.setProps({ aberta: true });
    await assentar();
    return aberta;
  };
  const conversa = arquivos => ({
    pessoa: { id: 23, name: 'Fábio Kalinoski' },
    arquivos,
  });

  it('carregando: esqueleto, sem botão de guardar', async () => {
    const w = await abrirCom({
      arquivosDaConversa: () => new Promise(() => {}),
    });

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('guardar-lembrete')).exists()).toBe(false);
  });

  it('erro ao abrir: a frase e Tentar de novo', async () => {
    const arquivosDaConversa = vi
      .fn()
      .mockRejectedValueOnce(new Error('falhou'))
      .mockResolvedValue(conversa([]));
    const w = await abrirCom({ arquivosDaConversa });

    expect(w.get(daCarteira('erro')).text()).toContain(
      'Não consegui abrir. Tente de novo.'
    );
    await w.get(`${daCarteira('erro')} button`).trigger('click');
    await assentar();

    // Vazio: nenhum arquivo veio na conversa; resta soltar um.
    expect(w.get(daCarteira('de-fora')).text()).toContain(
      'Nenhum arquivo veio nesta conversa.'
    );
    expect(w.get(daCarteira('de-fora')).text()).toContain(
      'Arraste o arquivo aqui ou clique para escolher'
    );
  });

  it('se a leitura ou o guardar falham, a tela diz e não perde o que foi escolhido', async () => {
    const lerDeFora = vi
      .fn()
      .mockRejectedValueOnce(new Error('falhou'))
      .mockResolvedValue({
        tipo: 'auto',
        seguradora: 'Seguradora Aurora',
        termina: 1803297600,
      });
    const w = await abrirCom({
      arquivosDaConversa: async () => conversa([{ nome: 'apolice.pdf' }]),
      lerDeFora,
      guardarDeFora: vi.fn().mockRejectedValue(new Error('falhou')),
    });

    await escolher(w, 'apolice.pdf');
    expect(w.get(daCarteira('de-fora-erro')).text()).toBe(
      'Não consegui ler. Tente de novo.'
    );

    await escolher(w, 'apolice.pdf');
    await responder(w, 'Sim, quer');
    await guardar(w);
    expect(w.get(daCarteira('de-fora-erro')).text()).toBe(
      'Não consegui guardar o lembrete. Tente de novo.'
    );
    expect(w.emitted('guardado')).toBeUndefined();
    expect(w.get(daCarteira('guardar-lembrete')).attributes('disabled')).toBe(
      undefined
    );
  });
});

describe('Tela 20: pela ficha da pessoa', () => {
  it('quem não tem seguro com a corretora ganha o seguro "Em outra corretora"', async () => {
    rota.query = { demo: 'cheio' };
    rota.params = { contactId: String(SEM_SEGURO) };
    const w = await montar(FichaDaPessoaPage);

    await w.get(daCarteira('ficha-guardar-de-fora')).trigger('click');
    await assentar();
    await escolher(w, 'apolice-auto.pdf');
    await responder(w, 'Sim, quer');
    await guardar(w);

    expect(w.get(`${daCarteira('seguros')} h2`).text()).toBe('Seguros (1)');
    const linha = textoDe(w, daCarteira('seguro'));
    expect(linha).toContain('Em outra corretora');
    expect(linha).toContain('Seguradora Aurora · está em outra corretora');
    expect(w.get(daCarteira('aviso-vivo')).text()).toContain(
      'Lembrete guardado. Vamos chamar '
    );
  });
});
