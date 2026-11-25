import {
  PAPEL,
  papeisDisponiveis,
  papelDoPasso,
  queryDeConversar,
  queryDeEscrever,
  queryDoPapel,
  temPasso2,
} from '../../constants/papeis';

// #3219 — as regras do "Criar agente" em dois passos: quais papéis a conta vê e para onde cada escolha leva.
const chaves = flags => papeisDisponiveis(flags).map(papel => papel.chave);

describe('papeis (#3219)', () => {
  describe('papeisDisponiveis', () => {
    it('shows only the customer agent and the Team copilot without Phase 2 nor the per inbox agent', () => {
      expect(chaves({ agentes: 3 })).toEqual([PAPEL.ATENDER, PAPEL.COPILOTO]);
    });

    it('adds the team agent and the helper with Phase 2 and agents on the account', () => {
      expect(chaves({ fase2: true, agentes: 1 })).toEqual([
        PAPEL.ATENDER,
        PAPEL.COPILOTO,
        PAPEL.EQUIPE,
        PAPEL.AJUDANTE,
      ]);
    });

    it('hides the helper when the account has no agent, even with Phase 2', () => {
      expect(chaves({ fase2: true, agentes: 0 })).toEqual([
        PAPEL.ATENDER,
        PAPEL.COPILOTO,
        PAPEL.EQUIPE,
      ]);
    });

    it('adds "another system" only with the per inbox agent', () => {
      expect(chaves({ porCaixa: true })).toEqual([
        PAPEL.ATENDER,
        PAPEL.COPILOTO,
        PAPEL.CONECTAR,
      ]);
    });

    it('keeps the customer agent first, the highlighted card', () => {
      expect(chaves({ fase2: true, porCaixa: true, agentes: 2 })[0]).toBe(
        PAPEL.ATENDER
      );
    });
  });

  describe('papelDoPasso', () => {
    it.each([
      [{ papel: 'atender' }, PAPEL.ATENDER],
      [{ papel: 'copiloto' }, PAPEL.COPILOTO],
      // As marcas da criação continuam da criação.
      [{ papel: 'area' }, null],
      [{ papel: 'ajudante' }, null],
      [{ papel: 'qualquer' }, null],
      [{}, null],
    ])('reads %o as %s', (query, papel) => {
      expect(papelDoPasso(query)).toBe(papel);
    });
  });

  describe('para onde a escolha leva', () => {
    it('only the customer agent and the copilot have a step 2', () => {
      expect(temPasso2(PAPEL.ATENDER)).toBe(true);
      expect(temPasso2(PAPEL.COPILOTO)).toBe(true);
      expect(temPasso2(PAPEL.EQUIPE)).toBe(false);
      expect(temPasso2(PAPEL.AJUDANTE)).toBe(false);
      expect(temPasso2(PAPEL.CONECTAR)).toBe(false);
    });

    it.each([
      [PAPEL.ATENDER, { papel: 'atender' }],
      [PAPEL.COPILOTO, { papel: 'copiloto' }],
      // Sem passo 2: as URLs de sempre.
      [PAPEL.EQUIPE, { papel: 'area' }],
      [PAPEL.AJUDANTE, { papel: 'ajudante' }],
      [PAPEL.CONECTAR, { conectar: 'outro' }],
    ])('choosing %s goes to %o', (papel, query) => {
      expect(queryDoPapel(papel)).toEqual(query);
    });

    it.each([
      [PAPEL.ATENDER, { modelo: 'custom' }],
      [PAPEL.COPILOTO, { atuacao: 'interno' }],
    ])('talking with the AI as %s keeps the URL of always', (papel, query) => {
      expect(queryDeConversar(papel)).toEqual(query);
    });

    it.each([
      [PAPEL.ATENDER, { escrever: '1', papel: 'atender' }],
      [PAPEL.COPILOTO, { escrever: '1', papel: 'copiloto' }],
    ])('writing it myself as %s carries the role', (papel, query) => {
      expect(queryDeEscrever(papel)).toEqual(query);
    });
  });
});
