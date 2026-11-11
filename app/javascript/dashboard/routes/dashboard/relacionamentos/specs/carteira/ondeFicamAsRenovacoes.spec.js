import { withFullI18n } from 'test-i18n';
import { useRoute } from 'vue-router';
import { ajustesDaDemo } from '../../demo/carteiraAjustes';
import { daCarteira, doBlocoA, semRolagem, textoDe } from './apoio';
import {
  abrirTrazer,
  assentarBem,
  carregarDemonstracaoDeTrazer,
  clicar,
  emFoco,
  fecharTrazer,
  ligarRelogio,
  passar,
} from './apoioDeTrazer';

// "Onde ficam as renovações?" (#2897, Tela 10): o passo que só aparece na
// primeira vez que a conta traz seguros, de qualquer jeito (planilha, PDFs ou
// Agger), antes da conferência.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relacionamentos_trazer' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query && !destino.name) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
// As fontes de demonstração sem as esperas de rede.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    trazerFonte: opcoes =>
      real.trazerFonte({ ...opcoes, atraso: 0, atrasoDaLeitura: 0 }),
  };
});
vi.mock('../../fonte/trazerSegurosFonte', async importOriginal => {
  const real = await importOriginal();
  return {
    ...real,
    trazerSegurosFonte: opcoes =>
      real.trazerSegurosFonte({ ...opcoes, atraso: 0 }),
  };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const TITULO = 'Onde ficam as renovações?';
const LEITURA_DOS_PDFS_MS = 12000;
const BUSCA_INTEIRA_MS = 8000;

const pelaPlanilha = async query => {
  const w = await abrirTrazer(rota, { como: 'planilha', ...query });
  await w.get(doBlocoA('usar-exemplo')).trigger('click');
  await assentarBem();
  await clicar(w, 'tem-seguros');
  return w;
};

beforeAll(async () => {
  semRolagem();
  await carregarDemonstracaoDeTrazer();
}, 60000);
beforeEach(ligarRelogio);
afterEach(() => {
  fecharTrazer();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe('Tela 10: onde ficam as renovações?', () => {
  it('já vem respondida com o padrão: criar o funil Renovação, 60 dias antes', async () => {
    const w = await pelaPlanilha();

    expect(w.get('h1').text()).toBe(TITULO);
    expect(emFoco()).toBe(w.get('h1').element);
    const criar = w.get(daCarteira('criar-funil'));
    expect(criar.attributes('aria-checked')).toBe('true');
    expect(criar.text()).toContain(
      'Já vem com os passos: A vencer, Cotando, Opções enviadas, Negociação, Renovado.'
    );
    expect(w.get(daCarteira('usar-funil')).text()).toBe(
      'Usar um funil que já tenho'
    );
    expect(w.find(daCarteira('escolher-funil')).exists()).toBe(false);
    expect(w.get(`${daCarteira('dias-antes')} input`).element.value).toBe('60');
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 60 dias, 22 seguros entram em renovação amanhã cedo.'
    );
    expect(w.get(daCarteira('continuar-renovacoes')).text()).toBe('Continuar');
  });

  it('quem só continua segue para a conferência, com o padrão guardado', async () => {
    const w = await pelaPlanilha();

    await clicar(w, 'continuar-renovacoes');

    expect(w.get('h1').text()).toBe('Achei 168 seguros de 120 pessoas.');
    expect(ajustesDaDemo()).toMatchObject({ onde: 'criar', dias: 60 });
    // Da conferência, o Voltar vai à pergunta dos seguros (a escolha já foi).
    await clicar(w, 'voltar-do-conferir');
    await clicar(w, 'tem-seguros');
    expect(w.get('h1').text()).toBe('Achei 168 seguros de 120 pessoas.');
  });

  it('usar um funil que já tenho: Continuar fica ligado, diz o que falta e leva o foco; a linha do efeito segue os dias', async () => {
    const w = await pelaPlanilha();

    await clicar(w, 'usar-funil');
    expect(w.find(daCarteira('escolher-etapa')).exists()).toBe(false);
    const continuar = w.get(daCarteira('continuar-renovacoes'));
    expect(continuar.attributes('disabled')).toBeUndefined();
    await clicar(w, 'continuar-renovacoes');

    const falta = w.get(daCarteira('falta-nas-renovacoes'));
    expect(falta.attributes('role')).toBe('alert');
    expect(falta.text()).toBe('Escolha o funil.');
    const funil = w.get(`${daCarteira('escolher-funil')} button`);
    expect(funil.attributes('aria-describedby')).toBe(falta.attributes('id'));
    expect(emFoco()).toBe(funil.element);
    expect(w.get('h1').text()).toBe(TITULO);

    await funil.trigger('click');
    const opcoes = w.findAll(`${daCarteira('escolher-funil')} [role="option"]`);
    expect(opcoes.map(o => o.text())).toEqual(['Vendas', 'Atendimento']);
    await opcoes[1].trigger('click');
    await assentarBem();
    // A primeira etapa do funil escolhido já vem escolhida.
    expect(w.get(`${daCarteira('escolher-etapa')} button`).text()).toContain(
      'Aberto'
    );
    expect(w.find(daCarteira('falta-nas-renovacoes')).exists()).toBe(false);
    expect(w.text()).toContain(
      'Quem cuida da renovação é quem já cuida desse funil.'
    );

    await w.get(`${daCarteira('dias-antes')} input`).setValue('30');
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 30 dias, 17 seguros entram em renovação amanhã cedo.'
    );
    await clicar(w, 'continuar-renovacoes');

    expect(w.get(daCarteira('efeito-renovacao')).text()).toBe(
      'Amanhã cedo, 17 seguros que vencem em até 30 dias entram em renovação.'
    );
    expect(ajustesDaDemo()).toMatchObject({
      onde: 'usar',
      funil: 'Atendimento',
      etapa: 'Aberto',
      dias: 30,
    });
  });

  it('sem permissão para mexer em funis: explica e deixa seguir sem escolher', async () => {
    const w = await pelaPlanilha({ caso: 'sem_permissao_de_funil' });

    expect(w.find('[role="radio"]').exists()).toBe(false);
    expect(textoDe(w, daCarteira('sem-permissao-de-funil'))).toBe(
      'Quem cuida dos funis da sua conta precisa fazer esta escolha. Os seguros entram do mesmo jeito; as renovações começam depois que a escolha for feita.'
    );
    const seguir = w.get(daCarteira('continuar-renovacoes'));
    expect(seguir.text()).toBe('Seguir sem escolher');

    await clicar(w, 'continuar-renovacoes');

    expect(w.get('h1').text()).toBe('Achei 168 seguros de 120 pessoas.');
    // Nenhuma renovação começa ainda: a linha do efeito não aparece.
    expect(w.find(daCarteira('efeito-renovacao')).exists()).toBe(false);
  });

  it('pelos PDFs: depois de ler, a mesma pergunta; Voltar devolve aos PDFs', async () => {
    const w = await abrirTrazer(rota, { como: 'pdfs' });
    await clicar(w, 'pdfs-usar-exemplo');
    await clicar(w, 'ler-pdfs');
    await passar(LEITURA_DOS_PDFS_MS);

    expect(w.get('h1').text()).toBe(TITULO);
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 60 dias, 6 seguros entram em renovação amanhã cedo.'
    );
    await clicar(w, 'continuar-renovacoes');
    expect(w.get('h1').text()).toBe(
      'Li 40 PDFs. Achei 39 seguros de 31 pessoas.'
    );
  });

  it('pelo Agger: depois da busca, a mesma pergunta antes de conferir', async () => {
    const w = await abrirTrazer(rota, { como: 'agger' });
    await w.get(daCarteira('agger-usuario')).setValue('corretora');
    await w.get(daCarteira('agger-senha')).setValue('exemplo');
    await clicar(w, 'agger-entrar');
    await passar(BUSCA_INTEIRA_MS);
    await clicar(w, 'agger-continuar');

    expect(w.get('h1').text()).toBe(TITULO);
    expect(textoDe(w, daCarteira('efeito-dias'))).toBe(
      'Com 60 dias, 21 seguros entram em renovação amanhã cedo.'
    );
    await clicar(w, 'continuar-renovacoes');
    expect(w.get('h1').text()).toBe('Achei 156 seguros de 116 pessoas.');
  });
});
