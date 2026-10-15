import { useSalvarEquipe } from '../composables/useSalvarEquipe';

// #1433 — gravar onde o agente da equipe fica: entra antes de sair, uma caixa por chamada, e nada é
// lembrado entre tentativas (a tela relê onde ele está e o servidor aceita repetir a entrada).
const canais = vi.hoisted(() => ({ connect: vi.fn(), disconnect: vi.fn() }));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canais }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

describe('useSalvarEquipe', () => {
  let ordem;
  beforeEach(() => {
    ordem = [];
    canais.connect.mockReset().mockImplementation(async (id, inbox, opcoes) => {
      ordem.push(`post:${inbox}:${opcoes.papel}`);
    });
    canais.disconnect.mockReset().mockImplementation(async (id, inbox) => {
      ordem.push(`delete:${inbox}`);
    });
  });

  it('enters before leaving, one inbox per call', async () => {
    const { salvar } = useSalvarEquipe();
    expect(
      await salvar({ agenteId: 7, nome: 'Bia', entram: [1, 2], saem: [3] })
    ).toBe(true);
    expect(ordem).toEqual(['post:1:area', 'post:2:area', 'delete:3']);
  });

  it('add, remove, add again: the second add really posts again', async () => {
    const { salvar } = useSalvarEquipe();
    await salvar({ agenteId: 7, nome: 'Bia', entram: [11] });
    await salvar({ agenteId: 7, nome: 'Bia', saem: [11] });
    await salvar({ agenteId: 7, nome: 'Bia', entram: [11] });
    expect(ordem).toEqual(['post:11:area', 'delete:11', 'post:11:area']);
  });

  it('stops at the first failure with the server reason, and the next try sends everything again', async () => {
    canais.connect.mockImplementation(async (id, inbox) => {
      ordem.push(`post:${inbox}`);
      if (inbox === 2) {
        throw Object.assign(new Error('422'), {
          response: { data: { error: 'Ninguém atende primeiro.' } },
        });
      }
    });
    const { salvar, erro, salvando } = useSalvarEquipe();
    expect(
      await salvar({ agenteId: 7, nome: 'Bia', entram: [1, 2, 3], saem: [4] })
    ).toBe(false);
    expect(ordem).toEqual(['post:1', 'post:2']);
    expect(erro.value.titulo).toBe('Ninguém atende primeiro.');
    expect(salvando.value).toBe(false);

    canais.connect.mockImplementation(async (id, inbox) => {
      ordem.push(`post:${inbox}`);
    });
    expect(
      await salvar({ agenteId: 7, nome: 'Bia', entram: [1, 2, 3], saem: [4] })
    ).toBe(true);
    expect(ordem.slice(2)).toEqual(['post:1', 'post:2', 'post:3', 'delete:4']);
    expect(erro.value).toBeNull();
  });

  it('falls back to its own message when the server says nothing', async () => {
    canais.connect.mockRejectedValue(new Error('offline'));
    const { salvar, erro } = useSalvarEquipe();
    await salvar({ agenteId: 7, nome: 'Bia', entram: [1] });
    expect(erro.value).toEqual({
      titulo: 'AGENTS.JORNADA.EQUIPE.ERRO',
      garantia: 'AGENTS.JORNADA.EQUIPE.ERRO_GARANTIA',
    });
  });
});
