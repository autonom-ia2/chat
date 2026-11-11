import { ref } from 'vue';
import { useFichaDaPessoa } from '../../ficha/useFichaDaPessoa';
import { useFichaDaEmpresa } from '../../ficha/useFichaDaEmpresa';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../../ficha/useEstadoDaFicha';

// O estado das fichas e o que acontece quando a fonte falha (#2894).
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
  guardarNota: vi.fn().mockResolvedValue({ id: 'b' }),
  salvar: vi.fn().mockResolvedValue({ ...pessoa, name: 'Ana Maria' }),
  liberarMensagens: vi.fn().mockResolvedValue(pessoa),
  ...extra,
});

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

  it('falha de leitura vira erro', async () => {
    const ficha = useFichaDaPessoa(
      fonteDaPessoa({ cards: vi.fn().mockRejectedValue(new Error('x')) }),
      ref(1)
    );
    await ficha.carregar();
    expect(ficha.estado.value).toBe(ESTADOS.ERRO);
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
});
