import {
  escolherDestino,
  lembrarDestino,
  lerUltimoDestino,
} from '../utils/destinoPronto';

const VENDAS = {
  id: 1,
  nome: 'Vendas',
  venda: true,
  etapas: [
    { id: 11, nome: 'Novo contato' },
    { id: 12, nome: 'Conversando' },
  ],
};
const REVENDA = {
  id: 2,
  nome: 'Revenda',
  venda: true,
  etapas: [{ id: 21, nome: 'Entrada' }],
};
const ATENDER = {
  id: 3,
  nome: 'Atendimento',
  venda: false,
  etapas: [{ id: 31, nome: 'Aberto' }],
};

describe('escolherDestino', () => {
  it('1º: o último que a pessoa escolheu, se ainda é de Vender', () => {
    const destino = escolherDestino({
      funis: [VENDAS, REVENDA],
      ultimo: { funilId: 2, etapaId: 21 },
      padrao: { funilId: 1, etapaId: 11 },
    });

    expect(destino.funil.nome).toBe('Revenda');
    expect(destino.etapa.nome).toBe('Entrada');
  });

  it('2º: o padrão da conta, quando o último não vale mais', () => {
    const destino = escolherDestino({
      funis: [VENDAS, REVENDA],
      ultimo: { funilId: 99, etapaId: 1 },
      padrao: { funilId: '1', etapaId: '12' },
    });

    expect(destino.funil.nome).toBe('Vendas');
    expect(destino.etapa.nome).toBe('Conversando');
  });

  it('o padrão em funil de Atender não vale', () => {
    const destino = escolherDestino({
      funis: [VENDAS, REVENDA, ATENDER],
      padrao: { funilId: 3, etapaId: 31 },
    });

    expect(destino).toBeNull();
  });

  it('3º: o único funil de Vender, na primeira etapa', () => {
    const destino = escolherDestino({ funis: [ATENDER, VENDAS] });

    expect(destino.funil.nome).toBe('Vendas');
    expect(destino.etapa.nome).toBe('Novo contato');
  });

  it('4º: com dois de Vender e nada guardado, não escolhe sozinho', () => {
    expect(escolherDestino({ funis: [VENDAS, REVENDA] })).toBeNull();
  });

  it('etapa que sumiu cai na primeira etapa do funil', () => {
    const destino = escolherDestino({
      funis: [VENDAS],
      ultimo: { funilId: 1, etapaId: 404 },
    });

    expect(destino.etapa.nome).toBe('Novo contato');
  });
});

describe('último destino no navegador', () => {
  beforeEach(() => window.localStorage.clear());

  it('guarda por conta e por usuário', () => {
    lembrarDestino(1, 7, { funilId: 2, etapaId: 21 });

    expect(lerUltimoDestino(1, 7)).toEqual({ funilId: 2, etapaId: 21 });
    expect(lerUltimoDestino(1, 8)).toBeNull();
  });

  it('sem navegador para ler, segue sem o último', () => {
    const espiao = vi
      .spyOn(Storage.prototype, 'getItem')
      .mockImplementation(() => {
        throw new Error('bloqueado');
      });

    expect(lerUltimoDestino(1, 7)).toBeNull();
    espiao.mockRestore();
  });
});
