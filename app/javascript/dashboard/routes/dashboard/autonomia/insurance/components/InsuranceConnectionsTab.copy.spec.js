import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import InsuranceConnectionsTab from './InsuranceConnectionsTab.vue';

// O TEXTO QUE O CORRETOR LÊ — com as mensagens de verdade.
//
// `InsuranceConnectionsTab.spec.js` roda com `messages: {}` e assere nas chaves, que é o certo para
// comportamento: não amarra o teste à cópia. Só que frase montada com plural, contagem e
// interpolação NÃO é comportamento — é o texto final, e com i18n vazio ele nunca chega a existir.
//
// Um QA independente provou o custo disso: havia um exemplo chamado `nao escreve "1 seguradoras"`,
// verde, enquanto a tela escrevia "0 de 1 seguradoras" em produção. O `t()` devolvia a chave crua e
// o `not.toContain` passava sem nunca ter renderizado a frase.
//
// Regra deste arquivo: asserção em português, sobre a string que aparece na tela.
withFullI18n();

const api = vi.hoisted(() => ({
  getConnection: vi.fn(),
  connect: vi.fn(),
  reconnect: vi.fn(),
  rescan: vi.fn(),
  removeConnection: vi.fn(),
}));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const seguradora = (code, name, refused = false) => ({
  code,
  name,
  enabled: !refused,
  integrationStatus: refused ? 'auth_required' : 'ready',
});

const conexao = produtos => ({
  provider: 'agger',
  status: 'ready',
  username_hint: 'co*******@exemplo.com.br',
  external_account_label: 'CORRETORA X',
  last_authenticated_at: '2026-09-07T13:00:00.000Z',
  last_healthcheck_at: '2026-09-07T13:00:00.000Z',
  last_capability_scan_at: '2026-09-07T13:00:00.000Z',
  encryption_available: true,
  layers: { runtime: 'ok', platform_auth: 'ok', insurer_auth: 'unknown' },
  capabilities: {
    products: produtos.map((p, i) => ({
      platformRef: String(700 + i),
      labelConfidence: 'confirmed',
      enabled: true,
      coveragePackages: [],
      ...p,
    })),
  },
});

const montar = async payload => {
  api.getConnection.mockResolvedValue({ data: { payload } });
  const wrapper = mount(InsuranceConnectionsTab);
  await flushPromises();
  return wrapper;
};

describe('o texto que a aba Conexões escreve', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
  });

  // O caso está no próprio desenho aprovado: Bike, uma seguradora.
  it('escreve "1 seguradora" no singular, nunca "1 seguradoras"', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('1', 'Porto')],
        },
      ])
    );
    expect(wrapper.text()).toContain('1 seguradora');
    expect(wrapper.text()).not.toContain('1 seguradoras');
  });

  // Mesma armadilha na outra contagem, a que tem denominador.
  it('escreve "0 de 1 seguradora" no singular', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('1', 'Azul', true)],
        },
      ])
    );
    expect(wrapper.text()).toContain('0 de 1 seguradora');
    expect(wrapper.text()).not.toContain('0 de 1 seguradoras');
  });

  // A CAMADA E O PRODUTO NÃO PODEM DAR NÚMEROS QUE SE CONTRADIZEM.
  //
  // A versão anterior contava as seguradoras da CONTA inteira e colava o número numa frase que
  // nomeava um PRODUTO: a camada dizia "recusou em Automóvel. As outras 22 passaram" enquanto a
  // linha do Automóvel dizia "17 de 18". Nenhum dos dois estava errado sozinho.
  it('a camada fala da conta, e o produto fala do produto', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [
            seguradora('1', 'Porto'),
            seguradora('2', 'Zurich'),
            seguradora('10', 'Azul', true),
          ],
        },
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('9', 'HDI')],
        },
      ])
    );
    const texto = wrapper.text();
    // 4 seguradoras distintas na conta, 1 recusada -> 3 passaram.
    expect(texto).toContain('Azul recusou o login da corretora.');
    expect(texto).toContain('As outras 3 seguradoras da conta passaram.');
    // E a linha do produto conta o universo DELE: 2 de 3.
    expect(texto).toContain('2 de 3 seguradoras');
    // O produto afetado é nomeado onde ele importa, não na camada.
    expect(texto).toContain('cotação de Automóvel');
  });

  // "As outras 0 passaram" é frase sem sentido, e o caso é alcançável: conta com uma seguradora só,
  // e ela recusou.
  it('nao escreve "As outras 0" quando nenhuma outra passou', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('10', 'Azul', true)],
        },
      ])
    );
    const texto = wrapper.text();
    expect(texto).not.toContain('As outras 0');
    expect(texto).toContain('Nenhuma outra seguradora da conta passou.');
  });

  // Plural do rótulo da camada, nas duas pontas.
  it('conta as recusadas no rotulo da camada, com plural certo', async () => {
    const uma = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'Porto'), seguradora('10', 'Azul', true)],
        },
      ])
    );
    expect(uma.text()).toContain('1 recusada');

    const duas = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [
            seguradora('1', 'Porto'),
            seguradora('10', 'Azul', true),
            seguradora('13', 'Mitsui', true),
          ],
        },
      ])
    );
    expect(duas.text()).toContain('2 recusadas');
  });

  // Sem recusa nenhuma, a camada afirma o que conferiu — e no plural certo.
  it('sem recusa, diz quantas foram conferidas', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'Porto'), seguradora('2', 'Zurich')],
        },
      ])
    );
    // Frase inteira: maiúscula e ponto final, como as outras duas camadas. Ela veio do mockup
    // como segunda metade de "A Azul recusou… As outras 17 foram conferidas…", e usada sozinha
    // ficava em minúscula e sem ponto ao lado de vizinhas pontuadas.
    expect(wrapper.text()).toContain(
      'As 2 foram conferidas uma a uma no portal e passaram.'
    );
  });

  // O veredito é a primeira frase da tela, e precisa concordar em número.
  it('o veredito concorda em numero', async () => {
    const um = await montar(
      conexao([
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('1', 'Porto')],
        },
      ])
    );
    expect(um.text()).toContain('Pronta para cotar 1 produto');
    expect(um.text()).not.toContain('1 produtos');

    const dois = await montar(
      conexao([
        {
          product: 'bike',
          label: 'Bike',
          insurers: [seguradora('1', 'Porto')],
        },
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('2', 'Zurich')],
        },
      ])
    );
    expect(dois.text()).toContain('Pronta para cotar 2 produtos');
  });

  // O VEREDITO NÃO PODE CONTRADIZER A LISTA. Produto habilitado no AGGER com zero seguradoras
  // respondendo não cota nada; contá-lo fazia a tela dizer "Pronta para cotar 2 produtos" tendo
  // "Bike 0 seguradoras" logo abaixo, com ponto verde que a legenda define como "cotando".
  it('nao conta como pronto o produto sem seguradora nenhuma', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'Porto')],
        },
        { product: 'bike', label: 'Bike', insurers: [] },
      ])
    );
    const texto = wrapper.text();
    expect(texto).toContain('Pronta para cotar 1 produto');
    expect(texto).not.toContain('Pronta para cotar 2 produtos');
    // A linha continua na tela — o corretor precisa ver que está parada — e diz por quê.
    expect(texto).toContain('Bike');
    expect(texto).toContain(
      'Nenhuma seguradora responde por este produto hoje.'
    );
  });

  // Com 2+ recusadas, "uma seguradora a menos" mentia: eram três.
  it('o aviso de dinheiro concorda com quantas recusaram', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [
            seguradora('1', 'Porto'),
            seguradora('10', 'Azul', true),
            seguradora('13', 'Mitsui', true),
            seguradora('14', 'Sompo', true),
          ],
        },
      ])
    );
    const texto = wrapper.text();
    expect(texto).toContain('1 de 4 seguradoras');
    expect(texto).toContain('3 seguradoras a menos');
    expect(texto).not.toContain('uma seguradora a menos');
    // Concordância verbal com lista de nomes.
    expect(texto).toContain('Azul, Mitsui, Sompo estão fora');
    expect(texto).toContain('Azul, Mitsui, Sompo recusaram o login');
  });

  // `check` vem do adapter sem normalização: valor novo do lado de lá não pode virar chave crua.
  it('evidencia desconhecida nao vira chave de i18n na tela', async () => {
    const base = conexao([
      { product: 'auto', label: 'Automóvel', insurers: [seguradora('1', 'P')] },
    ]);
    const wrapper = await montar({
      ...base,
      evidence: {
        check: 'sonda_que_ainda_nao_existe',
        at: base.last_healthcheck_at,
      },
    });
    const texto = wrapper.text();
    expect(texto).not.toContain('EVIDENCE');
    expect(texto).toContain('em 07/09');
  });

  // O cabeçalho da lista e o rótulo do `<details>` são texto do desenho aprovado, e sumiram sem
  // quebrar teste nenhum na prova de mutação do QA.
  it('mostra o cabecalho da lista e o rotulo do bloco de verificacao', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'P')],
        },
      ])
    );
    expect(wrapper.text()).toContain('O que esta conta cota hoje');
    expect(wrapper.text()).toContain('Como isto foi verificado');
  });

  // Nenhuma chave crua pode vazar para a tela: se uma faltar no JSON, o corretor lê
  // "INSURANCE.ALGUMA.COISA" no lugar da frase.
  it('nao vaza chave de i18n para a tela', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'Porto'), seguradora('10', 'Azul', true)],
        },
      ])
    );
    expect(wrapper.text()).not.toContain('INSURANCE.');
  });
});
