import { ref } from 'vue';
import { useFichaDaPessoa } from '../../ficha/useFichaDaPessoa';
import { useFichaDaEmpresa } from '../../ficha/useFichaDaEmpresa';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../../ficha/useEstadoDaFicha';
import { FALHA_DA_PARTE } from '../../ficha/falhas';

// O estado das fichas e o que acontece quando a fonte falha (#2894, #2895).
const pessoa = { id: 1, name: 'Ana' };
const fonteDaPessoa = (extra = {}) => ({
  pessoa: vi.fn().mockResolvedValue(pessoa),
  conversas: vi.fn().mockResolvedValue([{ id: 1 }]),
  cards: vi.fn().mockResolvedValue([]),
  notas: vi.fn().mockResolvedValue([{ id: 'a' }]),
  arquivos: vi.fn().mockResolvedValue([]),
  origem: vi.fn().mockResolvedValue(null),
  marcarCliente: vi
    .fn()
    .mockResolvedValue({ ...pessoa, contact_type: 'customer' }),
  desmarcarCliente: vi
    .fn()
    .mockResolvedValue({ ...pessoa, contact_type: 'lead' }),
  guardarNota: vi.fn().mockResolvedValue({ id: 'b' }),
  salvar: vi.fn().mockResolvedValue({ ...pessoa, name: 'Ana Maria' }),
  liberarMensagens: vi.fn().mockResolvedValue(pessoa),
  ...extra,
});

const erroComNome = name => Object.assign(new Error(name), { name });

const adiada = () => {
  let resolver;
  const promessa = new Promise(r => {
    resolver = r;
  });
  return { promessa, resolver };
};

describe('ordem dos pedidos', () => {
  it('a resposta velha é descartada quando já saiu outro pedido', async () => {
    const id = ref(1);
    const velha = adiada();
    const fonte = fonteDaPessoa({
      pessoa: vi
        .fn()
        .mockImplementationOnce(() => velha.promessa)
        .mockResolvedValue({ id: 2, name: 'Bia' }),
    });
    const ficha = useFichaDaPessoa(fonte, id);
    const primeira = ficha.carregar();
    id.value = 2;
    await ficha.carregar();
    velha.resolver({ id: 1, name: 'Ana' });
    await primeira;
    expect(ficha.pessoa.value.name).toBe('Bia');
    expect(ficha.estado.value).toBe(ESTADOS.PRONTO);
  });

  it('só carrega com id válido', () => {
    expect([1, 42].every(idValido)).toBe(true);
    expect([NaN, undefined, 0, -1, 1.5].some(idValido)).toBe(false);
  });
});

describe('useFichaDaPessoa', () => {
  it('carrega tudo e fica pronta', async () => {
    const ficha = useFichaDaPessoa(fonteDaPessoa(), ref(1));
    expect(ficha.estado.value).toBe(ESTADOS.CARREGANDO);
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.PRONTO);
    expect(ficha.pessoa.value).toEqual(pessoa);
    expect(ficha.conversas.value).toHaveLength(1);
  });

  it('pessoa que não existe vira "não achei"', async () => {
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({ pessoa: vi.fn().mockResolvedValue(null) }),
      ref(2)
    );
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.NAO_ACHEI);
  });

  it('falha ao ler a pessoa vira erro', async () => {
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({ pessoa: vi.fn().mockRejectedValue(new Error('x')) }),
      ref(1)
    );
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.ERRO);
  });

  it('a fonte dizer NAO_ACHEI vira "não achei"; SEM_ACESSO vira "sem acesso"', async () => {
    const com = async nome => {
      const ficha = useFichaDaPessoa(
        fonteDaPessoa({ pessoa: vi.fn().mockRejectedValue(erroComNome(nome)) }),
        ref(1)
      );
      await ficha.carregar();
      return ficha.estado.value;
    };
    expect(await com('NAO_ACHEI')).toBe(ESTADOS.NAO_ACHEI);
    expect(await com('SEM_ACESSO')).toBe(ESTADOS.SEM_ACESSO);
  });

  it('uma parte que falha não derruba a ficha: fica vazia e diz como falhou', async () => {
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({
        cards: vi.fn().mockRejectedValue(new Error('x')),
        arquivos: vi.fn().mockRejectedValue(erroComNome('SEM_ACESSO')),
      }),
      ref(1)
    );
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.PRONTO);
    expect(ficha.cards.value).toEqual([]);
    expect(ficha.falhas.value).toMatchObject({
      conversas: '',
      cards: FALHA_DA_PARTE.ERRO,
      arquivos: FALHA_DA_PARTE.SEM_ACESSO,
    });
    expect(ficha.conversas.value).toHaveLength(1);
  });

  it('tentar de novo relê só a parte que falhou', async () => {
    const fonte = fonteDaPessoa({
      cards: vi
        .fn()
        .mockRejectedValueOnce(new Error('x'))
        .mockResolvedValue([{ id: 9 }]),
    });
    const ficha = useFichaDaPessoa(fonte, ref(1));
    await ficha.carregar();
    await ficha.relerParte('cards');
    expect(ficha.cards.value).toEqual([{ id: 9 }]);
    expect(ficha.falhas.value.cards).toBe('');
    expect(fonte.pessoa).toHaveBeenCalledTimes(1);
    expect(fonte.conversas).toHaveBeenCalledTimes(1);
  });

  it('a parte relida de uma pessoa não entra na ficha de outra', async () => {
    const id = ref(1);
    const velha = adiada();
    const fonte = fonteDaPessoa({
      cards: vi
        .fn()
        .mockResolvedValueOnce([])
        .mockImplementationOnce(() => velha.promessa)
        .mockResolvedValue([{ id: 2 }]),
    });
    const ficha = useFichaDaPessoa(fonte, id);
    await ficha.carregar();
    const relendo = ficha.relerParte('cards');
    id.value = 2;
    await ficha.carregar();
    velha.resolver([{ id: 1 }]);
    await relendo;
    expect(ficha.cards.value).toEqual([{ id: 2 }]);
  });

  it('guardar nota põe a nova no topo, sem mexer na lista antiga', async () => {
    const ficha = useFichaDaPessoa(fonteDaPessoa(), ref(1));
    await ficha.carregar();
    const antes = ficha.notas.value;
    expect(await ficha.guardarNota('texto')).toBe(true);
    expect(ficha.notas.value.map(n => n.id)).toEqual(['b', 'a']);
    expect(antes.map(n => n.id)).toEqual(['a']);
  });

  it('devolve false quando a escrita falha e solta o "ocupado"', async () => {
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({ salvar: vi.fn().mockRejectedValue(new Error('x')) }),
      ref(1)
    );
    await ficha.carregar();
    expect(await ficha.salvar({})).toBe(false);
    expect(ficha.ocupado.value).toBe('');
    expect(ficha.pessoa.value).toEqual(pessoa);
  });

  it('marcar como cliente troca a pessoa e relê os cards', async () => {
    const fonte = fonteDaPessoa();
    const ficha = useFichaDaPessoa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.marcarCliente()).toBe(true);
    expect(ficha.pessoa.value.contact_type).toBe('customer');
    expect(fonte.cards).toHaveBeenCalledTimes(2);
  });

  it('desmarcar cliente troca a pessoa e fica ocupado enquanto grava', async () => {
    const gravando = adiada();
    const fonte = fonteDaPessoa({
      pessoa: vi
        .fn()
        .mockResolvedValue({ ...pessoa, contact_type: 'customer' }),
      desmarcarCliente: vi.fn(() => gravando.promessa),
    });
    const ficha = useFichaDaPessoa(fonte, ref(1));
    await ficha.carregar();
    const desmarcando = ficha.desmarcarCliente();
    expect(ficha.ocupado.value).toBe('desmarcarCliente');
    gravando.resolver({ ...pessoa, contact_type: 'lead' });
    expect(await desmarcando).toBe(true);
    expect(fonte.desmarcarCliente).toHaveBeenCalledWith(1);
    expect(ficha.pessoa.value.contact_type).toBe('lead');
    expect(ficha.ocupado.value).toBe('');
  });

  it('desmarcar cliente que falha devolve false e deixa a pessoa como estava', async () => {
    const cliente = { ...pessoa, contact_type: 'customer' };
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({
        pessoa: vi.fn().mockResolvedValue(cliente),
        desmarcarCliente: vi.fn().mockRejectedValue(new Error('x')),
      }),
      ref(1)
    );
    await ficha.carregar();
    expect(await ficha.desmarcarCliente()).toBe(false);
    expect(ficha.pessoa.value).toEqual(cliente);
  });

  // A ficha troca de pessoa sem desmontar a tela: a resposta de uma escrita
  // que saiu para a pessoa de antes não pode cair na pessoa de agora.
  it.each([
    ['marcarCliente', 'marcarCliente', []],
    ['desmarcarCliente', 'desmarcarCliente', []],
    ['salvar', 'salvar', [{}]],
    ['liberar', 'liberarMensagens', []],
  ])(
    '%s: a resposta da pessoa de antes não entra na ficha de outra',
    async (acao, naFonte, argumentos) => {
      const id = ref(1);
      const velha = adiada();
      const outra = { id: 2, name: 'Bruno' };
      const fonte = fonteDaPessoa({
        pessoa: vi.fn().mockResolvedValueOnce(pessoa).mockResolvedValue(outra),
        [naFonte]: vi.fn(() => velha.promessa),
      });
      const ficha = useFichaDaPessoa(fonte, id);
      await ficha.carregar();
      const escrevendo = ficha[acao](...argumentos);
      id.value = 2;
      await ficha.carregar();
      velha.resolver({ ...pessoa, name: 'Ana de antes' });
      expect(await escrevendo).toBe(true);
      expect(ficha.pessoa.value).toEqual(outra);
    }
  );

  it('a nota guardada na pessoa de antes não entra nas notas de outra', async () => {
    const id = ref(1);
    const velha = adiada();
    const fonte = fonteDaPessoa({
      notas: vi
        .fn()
        .mockResolvedValueOnce([{ id: 'a' }])
        .mockResolvedValue([{ id: 'z' }]),
      guardarNota: vi.fn(() => velha.promessa),
    });
    const ficha = useFichaDaPessoa(fonte, id);
    await ficha.carregar();
    const guardando = ficha.guardarNota('texto');
    id.value = 2;
    await ficha.carregar();
    velha.resolver({ id: 'b' });
    expect(await guardando).toBe(true);
    expect(ficha.notas.value.map(n => n.id)).toEqual(['z']);
  });

  it('marcar como cliente deu certo mesmo se os cards não puderem ser relidos', async () => {
    const fonte = fonteDaPessoa({
      cards: vi
        .fn()
        .mockResolvedValueOnce([])
        .mockRejectedValue(erroComNome('SEM_ACESSO')),
    });
    const ficha = useFichaDaPessoa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.marcarCliente()).toBe(true);
    expect(ficha.pessoa.value.contact_type).toBe('customer');
    expect(ficha.falhas.value.cards).toBe(FALHA_DA_PARTE.SEM_ACESSO);
  });
});

describe('useFichaDaEmpresa', () => {
  const fonte = (extra = {}) => ({
    empresa: vi.fn().mockResolvedValue({ id: 1 }),
    pessoasDaEmpresa: vi.fn().mockResolvedValue([{ id: 7 }]),
    conversasDaEmpresa: vi.fn().mockResolvedValue([]),
    cardsDaEmpresa: vi.fn().mockResolvedValue([]),
    ...extra,
  });

  it('carrega a empresa e as pessoas dela', async () => {
    const ficha = useFichaDaEmpresa(fonte(), ref(1));
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.PRONTO);
    expect(ficha.pessoas.value).toEqual([{ id: 7 }]);
  });

  it('não acha e erro', async () => {
    const naoAchei = useFichaDaEmpresa(
      fonte({ empresa: vi.fn().mockResolvedValue(null) }),
      ref(1)
    );
    await naoAchei.carregar();
    expect(naoAchei.estado.value).toBe(ESTADOS.NAO_ACHEI);
    const erro = useFichaDaEmpresa(
      fonte({ empresa: vi.fn().mockRejectedValue(new Error('x')) }),
      ref(1)
    );
    await erro.carregar();
    expect(erro.estado.value).toBe(ESTADOS.ERRO);
  });

  it('uma parte que falha não derruba a ficha, e dá para tentar de novo', async () => {
    const leituras = fonte({
      cardsDaEmpresa: vi
        .fn()
        .mockRejectedValueOnce(erroComNome('SEM_ACESSO'))
        .mockResolvedValue([{ id: 4 }]),
      conversasDaEmpresa: vi.fn().mockRejectedValue(new Error('x')),
    });
    const ficha = useFichaDaEmpresa(leituras, ref(1));
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.PRONTO);
    expect(ficha.pessoas.value).toEqual([{ id: 7 }]);
    expect(ficha.falhas.value).toMatchObject({
      pessoas: '',
      conversas: FALHA_DA_PARTE.ERRO,
      cards: FALHA_DA_PARTE.SEM_ACESSO,
    });
    await ficha.relerParte('cards');
    expect(ficha.cards.value).toEqual([{ id: 4 }]);
    expect(ficha.falhas.value.cards).toBe('');
  });
});

describe('useFichaDaEmpresa: salvar com guarda de geração', () => {
  it('se o id mudar durante o salvamento, a resposta velha não sobrescreve', async () => {
    const id = ref(1);
    const velha = adiada();
    const fonte = {
      empresa: vi
        .fn()
        .mockImplementation(async i => ({ id: i, name: `E${i}` })),
      pessoasDaEmpresa: vi.fn().mockResolvedValue([]),
      conversasDaEmpresa: vi.fn().mockResolvedValue([]),
      cardsDaEmpresa: vi.fn().mockResolvedValue([]),
      salvarEmpresa: vi.fn().mockImplementation(() => velha.promessa),
    };
    const ficha = useFichaDaEmpresa(fonte, id);
    await ficha.carregar();
    const salvando = ficha.salvar({ name: 'Velha' });
    id.value = 2;
    await ficha.carregar();
    velha.resolver({ id: 1, name: 'Velha' });
    await salvando;
    expect(ficha.empresa.value).toMatchObject({ id: 2, name: 'E2' });
    expect(ficha.ocupado.value).toBe('');
  });

  it('sem troca de id, salvar atualiza a empresa', async () => {
    const fonte = {
      empresa: vi.fn().mockResolvedValue({ id: 1, name: 'E1' }),
      pessoasDaEmpresa: vi.fn().mockResolvedValue([]),
      conversasDaEmpresa: vi.fn().mockResolvedValue([]),
      cardsDaEmpresa: vi.fn().mockResolvedValue([]),
      salvarEmpresa: vi.fn().mockResolvedValue({ id: 1, name: 'Nova' }),
    };
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.salvar({ name: 'Nova' })).toBe(true);
    expect(ficha.empresa.value.name).toBe('Nova');
  });
});
