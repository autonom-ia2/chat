import { fichaFonte } from '../../fonte/fichaFonte';
import { demoDaFicha, esquecerEscritas } from '../../demo/ficha';
import { pessoas } from '../../demo/base';
import { semAcento } from '../../fonte/texto';

// A fonte da ficha e os dados fictícios dela (#2894).
const ID_CLIENTE_COMPLETO = 23;
const ID_RECUSOU_MANUAL = 203;
const ID_NUNCA_CONVERSOU = 39;
const ID_EMPRESA_COM_GENTE = 2;
const ID_QUE_NAO_EXISTE = 9999;

const fonte = fichaFonte({ demo: 'cheio', atraso: 0 });

beforeEach(esquecerEscritas);

describe('fichaFonte sem demonstração', () => {
  it('diz FONTE_REAL_PENDENTE em todo método', async () => {
    const real = fichaFonte({ demo: null });
    expect(real.usaDemo).toBe(false);
    await expect(real.pessoa(1)).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
    await expect(real.guardarNota(1, 'x')).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
  });

  it('ignora a demonstração quando o módulo não existe (produção)', async () => {
    const real = fichaFonte({ demo: 'cheio', carregarDemo: null });
    expect(real.usaDemo).toBe(false);
  });
});

describe('fichaFonte com ?demo=vazio', () => {
  const vazia = fichaFonte({ demo: 'vazio', atraso: 0 });

  it('não acha ninguém e lista nada', async () => {
    expect(await vazia.pessoa(1)).toBeNull();
    expect(await vazia.empresa(1)).toBeNull();
    expect(await vazia.conversas(1)).toEqual([]);
    expect(await vazia.pessoasDaEmpresa(1)).toEqual([]);
  });

  it('recusa escrita com "não achei"', async () => {
    await expect(vazia.salvar(1, {})).rejects.toMatchObject({
      name: 'NAO_ACHEI',
    });
  });
});

describe('dados da demonstração', () => {
  // Os horários são "tantos dias atrás" a partir de agora: com o relógio
  // parado, duas leituras seguidas não cruzam a virada de um segundo.
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-11T12:00:00Z'));
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('são sempre os mesmos para o mesmo id', async () => {
    expect(await fonte.conversas(ID_CLIENTE_COMPLETO)).toEqual(
      await fonte.conversas(ID_CLIENTE_COMPLETO)
    );
    expect(await fonte.cards(ID_CLIENTE_COMPLETO)).toEqual(
      await fonte.cards(ID_CLIENTE_COMPLETO)
    );
  });

  it('dão a quem é cliente conversas, cards, notas e arquivos', async () => {
    const [pessoa, conversas, cards, notas, arquivos, origem] =
      await Promise.all([
        fonte.pessoa(ID_CLIENTE_COMPLETO),
        fonte.conversas(ID_CLIENTE_COMPLETO),
        fonte.cards(ID_CLIENTE_COMPLETO),
        fonte.notas(ID_CLIENTE_COMPLETO),
        fonte.arquivos(ID_CLIENTE_COMPLETO),
        fonte.origem(ID_CLIENTE_COMPLETO),
      ]);
    expect(pessoa.contact_type).toBe('customer');
    expect(conversas.length).toBeGreaterThan(3);
    expect(cards.length).toBeGreaterThan(0);
    expect(notas.length).toBeGreaterThan(0);
    expect(arquivos.length).toBeGreaterThan(0);
    expect(['lista', 'canal']).toContain(origem.tipo);
  });

  it('dão a todo cliente ao menos um card ganho', () => {
    const clientes = pessoas().filter(p => p.contact_type === 'customer');
    expect(clientes.length).toBeGreaterThan(0);
    clientes.forEach(cliente => {
      expect(
        demoDaFicha.cards(cliente.id).some(c => c.situacao === 'ganho')
      ).toBe(true);
    });
  });

  it('não dão conversa nem arquivo a quem nunca conversou', () => {
    const quietos = pessoas().filter(p => !p.last_activity_at);
    expect(quietos.length).toBeGreaterThan(0);
    quietos.forEach(quieto => {
      expect(demoDaFicha.conversas(quieto.id)).toEqual([]);
      expect(demoDaFicha.arquivos(quieto.id)).toEqual([]);
    });
  });

  it('ordenam as conversas da mais nova para a mais antiga', async () => {
    const conversas = await fonte.conversas(ID_CLIENTE_COMPLETO);
    const quandos = conversas.map(c => c.quando);
    expect(quandos).toEqual([...quandos].sort((a, b) => b - a));
  });

  it('trazem informações criadas pela conta e a pessoa que recusou com origem', async () => {
    const recusou = await fonte.pessoa(ID_RECUSOU_MANUAL);
    expect(recusou.opted_out_at).toBeTruthy();
    expect(recusou.opt_out_source).toBe('manual');
    const sem = await fonte.pessoa(ID_NUNCA_CONVERSOU);
    expect(sem.last_activity_at).toBeNull();
  });

  it('não têm nada de seguro nos textos', () => {
    const texto = JSON.stringify(
      demoDaFicha.conversas(ID_CLIENTE_COMPLETO)
    ).toLowerCase();
    expect(texto).not.toContain('seguro');
    expect(texto).not.toContain('apólice');
  });
});

describe('escritas da demonstração', () => {
  it('salvar guarda na memória e devolve cópia nova', async () => {
    const antes = await fonte.pessoa(ID_CLIENTE_COMPLETO);
    const dados = {
      name: 'Nome Novo',
      email: 'novo@exemplo.com.br',
      phone_number: antes.phone_number,
      additional_attributes: {
        city: 'Bauru',
        company_name: antes.additional_attributes.company_name,
      },
      custom_attributes: { cpf: '52998224725' },
    };
    const copiaDosDados = JSON.stringify(dados);
    const salvo = await fonte.salvar(ID_CLIENTE_COMPLETO, dados);
    expect(salvo.name).toBe('Nome Novo');
    expect(
      (await fonte.pessoa(ID_CLIENTE_COMPLETO)).additional_attributes.city
    ).toBe('Bauru');
    expect(JSON.stringify(dados)).toBe(copiaDosDados);
    expect(salvo).not.toBe(await fonte.pessoa(ID_CLIENTE_COMPLETO));
    expect(antes.name).not.toBe('Nome Novo');
  });

  it('marcar como cliente vale na hora e dá um card ganho', async () => {
    expect((await fonte.pessoa(ID_NUNCA_CONVERSOU)).contact_type).toBe('lead');
    const cliente = await fonte.marcarCliente(ID_NUNCA_CONVERSOU);
    expect(cliente.contact_type).toBe('customer');
    expect(cliente.customer_since).toBeGreaterThan(0);
    const cards = await fonte.cards(ID_NUNCA_CONVERSOU);
    expect(cards.some(c => c.situacao === 'ganho')).toBe(true);
  });

  it('guardar nota põe a nota no topo, com quem escreveu', async () => {
    const antes = await fonte.notas(ID_CLIENTE_COMPLETO);
    const nota = await fonte.guardarNota(
      ID_CLIENTE_COMPLETO,
      'Ligar na segunda.'
    );
    const depois = await fonte.notas(ID_CLIENTE_COMPLETO);
    expect(depois).toHaveLength(antes.length + 1);
    expect(depois[0]).toMatchObject({
      id: nota.id,
      texto: 'Ligar na segunda.',
      autor: 'Você',
    });
  });

  it('liberar mensagens tira o pedido de parar', async () => {
    const liberada = await fonte.liberarMensagens(ID_RECUSOU_MANUAL);
    expect(liberada.opted_out_at).toBeNull();
    expect(liberada.opt_out_source).toBeNull();
    expect((await fonte.pessoa(ID_RECUSOU_MANUAL)).opted_out_at).toBeNull();
  });

  it('escrita em quem não existe diz "não achei"', async () => {
    await expect(fonte.marcarCliente(ID_QUE_NAO_EXISTE)).rejects.toMatchObject({
      name: 'NAO_ACHEI',
    });
    expect(await fonte.pessoa(ID_QUE_NAO_EXISTE)).toBeNull();
  });
});

describe('empresa', () => {
  it('traz a empresa, as pessoas dela, as conversas e os cards', async () => {
    const [empresa, gente, conversas, cards] = await Promise.all([
      fonte.empresa(ID_EMPRESA_COM_GENTE),
      fonte.pessoasDaEmpresa(ID_EMPRESA_COM_GENTE),
      fonte.conversasDaEmpresa(ID_EMPRESA_COM_GENTE),
      fonte.cardsDaEmpresa(ID_EMPRESA_COM_GENTE),
    ]);
    expect(empresa.contacts_count).toBe(gente.length);
    expect(gente.every(p => p.company_id === ID_EMPRESA_COM_GENTE)).toBe(true);
    expect(conversas.every(c => c.pessoa)).toBe(true);
    expect(cards.every(c => c.pessoa)).toBe(true);
    const quandos = conversas.map(c => c.quando);
    expect(quandos).toEqual([...quandos].sort((a, b) => b - a));
  });

  it('não acha empresa que não existe', async () => {
    expect(await fonte.empresa(ID_QUE_NAO_EXISTE)).toBeNull();
  });
});

describe('redes sociais fictícias', () => {
  it('sem acento, e o LinkedIn tem formato diferente do Instagram', async () => {
    const todas = await Promise.all(pessoas().map(p => fonte.pessoa(p.id)));
    const perfis = todas.flatMap(p =>
      Object.entries(p.additional_attributes.social_profiles)
    );
    expect(perfis.length).toBeGreaterThan(0);
    perfis.forEach(([, usuario]) => expect(usuario).toBe(semAcento(usuario)));
    const insta = perfis.find(([rede]) => rede === 'instagram')[1];
    const linkedin = perfis.find(([rede]) => rede === 'linkedin')[1];
    expect(insta.startsWith('@')).toBe(true);
    expect(linkedin.startsWith('@')).toBe(false);
    expect(linkedin).toContain('-');
  });
});
