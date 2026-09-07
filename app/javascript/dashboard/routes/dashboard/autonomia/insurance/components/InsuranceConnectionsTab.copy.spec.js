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

  // AS TRÊS GUARDAS DO DADO CRU DE `capabilities`.
  //
  // Elas existem e fazem a coisa certa, mas o QA da rodada final registrou que as três mutações
  // que as revertem SOBREVIVIAM: comportamento correto sem teste que o trave é a mesma dívida que
  // já reprovou esta branch duas vezes. `capabilities` é o único dos quatro caminhos crus que nem
  // passa pelo `sanitize_deep` do Rails, então é o que menos pode depender de disciplina.
  it('produto sem a chave `insurers` nao derruba a aba', async () => {
    const wrapper = await montar(
      conexao([{ product: 'auto', label: 'Automóvel' }])
    );
    const texto = wrapper.text();
    // A aba renderiza: sem a guarda, `insurers.some` estoura em `undefined` e a tela fica branca.
    expect(texto).toContain('Automóvel');
    expect(texto).toContain('0 seguradoras');
    expect(texto).toContain(
      'Nenhuma seguradora responde por este produto hoje.'
    );
  });

  // `enabled` é quem decide se cota. `integrationStatus` só qualifica POR QUE está fora, e não
  // pode desmentir — quando desmentia, o denominador contava por um e o aviso nomeava pelo outro.
  it('enabled manda sobre integrationStatus na contagem', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [
            {
              code: '1',
              name: 'Porto',
              enabled: true,
              integrationStatus: 'ready',
            },
            // O dado se contradiz: diz `ready` e diz que não está habilitada.
            {
              code: '2',
              name: 'Zurich',
              enabled: false,
              integrationStatus: 'ready',
            },
          ],
        },
      ])
    );
    expect(wrapper.text()).toContain('1 de 2 seguradoras');
  });

  // Slug sem `label` e sem tradução escrevia `ramo_100` na tela — o corretor lendo um
  // identificador nosso onde esperava o nome do produto.
  it('slug sem label vira "Ramo N", e nunca o slug cru', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'ramo_100',
          platformRef: '100',
          insurers: [seguradora('1', 'Porto')],
        },
      ])
    );
    const texto = wrapper.text();
    expect(texto).toContain('Ramo 100');
    expect(texto).not.toContain('ramo_100');
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

  // A GUARDA DERIVADA: o texto inteiro da tela, congelado.
  //
  // A versão anterior desta guarda era uma LISTA ESCRITA À MÃO de 19 frases, e um QA independente
  // passou nove mudanças visíveis por ela — inclusive a perda das duas datas do desenho e uma
  // quebra de concordância. Lista à mão cobre o que quem escreveu lembrou; é cobertura por caso
  // com outro nome.
  //
  // Aqui o snapshot é derivado do que a tela RENDERIZA. Qualquer frase que mude, suma, apareça,
  // troque de ordem ou perca plural quebra o exemplo — sem ninguém precisar prever qual. Mudança
  // de cópia deixa de ser silenciosa e passa a exigir `-u` e revisão do diff, que é exatamente o
  // portão que faltava.
  //
  // As asserções específicas abaixo continuam: elas dizem POR QUE cada frase é o que é, e o
  // snapshot sozinho não ensina isso a quem vier depois.
  const CENARIOS_DO_SNAPSHOT = {
    'conta saudavel, tres cores de ponto': [
      {
        product: 'auto',
        label: 'Automóvel',
        insurers: [seguradora('1', 'Porto'), seguradora('10', 'Azul', true)],
      },
      {
        product: 'residencial',
        label: 'Residencial',
        insurers: [seguradora('2', 'Zurich')],
      },
      { product: 'bike', label: 'Bike', insurers: [] },
    ],
    'produto unico, uma seguradora': [
      { product: 'bike', label: 'Bike', insurers: [seguradora('1', 'Porto')] },
    ],
    'unica seguradora recusada': [
      {
        product: 'bike',
        label: 'Bike',
        insurers: [seguradora('10', 'Azul', true)],
      },
    ],
    'tres recusadas no mesmo produto': [
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
    ],
    'conta sem produto nenhum': [],
  };

  Object.entries(CENARIOS_DO_SNAPSHOT).forEach(([nome, produtos]) => {
    it(`texto da tela — ${nome}`, async () => {
      const wrapper = await montar(conexao(produtos));
      // OS RÓTULOS DE BOTÃO NÃO ESTÃO EM `text()`. `vitest.setup.js` stuba `NextButton` como
      // `<button><slot/></button>` e descarta o prop `label` — os quatro botões do desenho
      // (Reconectar, Atualizar produtos, Desconectar, Conectar AGGER) ficavam invisíveis para o
      // snapshot, e um QA independente trocou os quatro por outra coisa com a suíte verde.
      // Aqui eles entram pelo atributo, que é onde o stub os deixa.
      const botoes = wrapper
        .findAll('button')
        .map(b => b.attributes('label') || b.text())
        .filter(Boolean);
      // Espaços normalizados: `text()` do vue-test-utils preserva a indentação do template, e o
      // snapshot passaria a acusar reformatação em vez de mudança de cópia.
      expect({
        texto: wrapper.text().split(/\s+/).join(' ').trim(),
        botoes,
      }).toMatchSnapshot();
    });
  });

  // AS FRASES DO DESENHO APROVADO, TODAS, NUMA LISTA SÓ.
  //
  // Três rodadas de QA acharam defeito novo a cada vez, e a explicação é sempre a mesma: eu
  // consertava o CASO e não a CLASSE. A prova de mutação da última rodada trocou seis frases do
  // desenho por "XXX" — legenda, rodapé, subtítulo da lista, nome de camada, detalhe do login — e
  // a suíte ficou verde nas seis.
  //
  // Esta lista é a guarda de classe. Toda frase que o corretor lê numa tela saudável entra aqui;
  // trocar qualquer uma por outra coisa derruba este exemplo. Frase nova do desenho entra na
  // lista, não num `it` próprio.
  it('escreve todas as frases do desenho aprovado', async () => {
    const wrapper = await montar(
      conexao([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'Porto'), seguradora('10', 'Azul', true)],
        },
        // Um produto de cada cor, para que as três entradas da legenda apareçam.
        {
          product: 'residencial',
          label: 'Residencial',
          insurers: [seguradora('2', 'Zurich')],
        },
        { product: 'bike', label: 'Bike', insurers: [] },
      ])
    );
    const texto = wrapper.text();
    [
      // Veredito e identificação
      'Pronta para cotar 2 produtos',
      'AGGER · Aggilizador',
      'CORRETORA X',
      // Bloco de verificação
      'Como isto foi verificado',
      'Cada camada tem prova própria',
      'O serviço da Autonom.ia responde',
      'Verificado agora, junto com a sessão.',
      'A conta abre sessão no AGGER',
      'Verificamos a cada 30 minutos.',
      'Credenciais nas seguradoras',
      // Lista de produtos
      'O que esta conta cota hoje',
      'Cada produto mostra quantas seguradoras respondem por ele.',
      'Automóvel',
      'Bike',
      // Legenda: as três cores que esta tela mostra
      'cotando',
      'alguma seguradora aguardando credencial',
      'sem seguradora respondendo',
      // Rodapé
      'Produto que a corretora não tem habilitado no AGGER não aparece aqui.',
      'a Autonom.ia lê o que a sua conta já pode vender',
    ].forEach(frase => expect(texto).toContain(frase));
  });

  // A LEGENDA DESCREVE AS CORES QUE ESTÃO NA TELA — nem a mais, nem a menos.
  //
  // O defeito: três cores de ponto e duas entradas de legenda, e a cor que faltava era a do
  // produto cuja única seguradora foi recusada — ponto cinza ao lado de uma caixa âmbar dizendo
  // "credencial recusada", na mesma linha.
  // Lê a legenda do DOM, e não do texto corrido: "Não está cotando" CONTÉM "cotando", e uma
  // asserção por substring solta dava falso negativo — o teste precisa comparar conjuntos, que é
  // o que a regra realmente diz.
  const coresEmTela = async produtos => {
    const wrapper = await montar(conexao(produtos));
    // `section ul li` e não `li`: as camadas do `<details>` também são `li` com ponto de cor, e
    // pegá-las junto misturava dois vocabulários de cor diferentes na mesma asserção.
    const daLinha = wrapper
      .findAll('section ul li span.size-2')
      .map(n => n.classes().find(c => c.startsWith('bg-')));
    const daLegenda = wrapper
      .findAll('div.flex-wrap > span.items-center span.size-2')
      .map(n => n.classes().find(c => c.startsWith('bg-')));
    return {
      daLinha: [...new Set(daLinha)].sort(),
      daLegenda: daLegenda.sort(),
    };
  };

  it('cada cor de ponto na tela tem entrada na legenda, e vice-versa', async () => {
    // Só cotando.
    expect(
      await coresEmTela([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'P')],
        },
      ])
    ).toEqual({ daLinha: ['bg-n-teal-9'], daLegenda: ['bg-n-teal-9'] });

    // ÚNICA SEGURADORA RECUSADA: âmbar, nunca cinza. Cinza aqui punha o ponto em desacordo com a
    // caixa âmbar "credencial recusada" que aparece na mesma linha.
    expect(
      await coresEmTela([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('10', 'Azul', true)],
        },
      ])
    ).toEqual({ daLinha: ['bg-n-amber-9'], daLegenda: ['bg-n-amber-9'] });

    // Sem seguradora nenhuma: cinza, e a legenda ganha a terceira entrada.
    expect(
      await coresEmTela([{ product: 'bike', label: 'Bike', insurers: [] }])
    ).toEqual({ daLinha: ['bg-n-slate-7'], daLegenda: ['bg-n-slate-7'] });

    // As três juntas, na ordem da legenda.
    expect(
      await coresEmTela([
        {
          product: 'auto',
          label: 'Automóvel',
          insurers: [seguradora('1', 'P')],
        },
        {
          product: 'residencial',
          label: 'Residencial',
          insurers: [seguradora('2', 'Z'), seguradora('10', 'Azul', true)],
        },
        { product: 'bike', label: 'Bike', insurers: [] },
      ])
    ).toEqual({
      daLinha: ['bg-n-amber-9', 'bg-n-slate-7', 'bg-n-teal-9'],
      daLegenda: ['bg-n-teal-9', 'bg-n-amber-9', 'bg-n-slate-7'].sort(),
    });
  });

  // A camada não pode promover "não havia o que verificar" a "verificado e passou".
  it('sem seguradora nenhuma, a camada continua nao verificada', async () => {
    const wrapper = await montar(
      conexao([{ product: 'bike', label: 'Bike', insurers: [] }])
    );
    const texto = wrapper.text();
    expect(texto).not.toContain('As 0 foram conferidas');
    expect(texto).not.toContain('foram conferidas uma a uma');
    expect(texto).toContain('não verificado');
  });

  // Conta conectada sem produto nenhum: some a lista, fica a explicação.
  it('sem produto, explica em vez de sumir com o card', async () => {
    const wrapper = await montar(conexao([]));
    const texto = wrapper.text();
    expect(texto).toContain('O que esta conta cota hoje');
    expect(texto).toContain(
      'Esta conta não tem nenhum produto habilitado no AGGER.'
    );
    expect(texto).toContain(
      'Produto que a corretora não tem habilitado no AGGER não aparece aqui.'
    );
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
