import { resumoOnde } from '../utils/resumoOnde';

// #1720 — a frase única do herói e do resumo "Onde e quando responde".
const t = (chave, valores = {}, n = undefined) =>
  [chave, JSON.stringify(valores), n].filter(v => v !== undefined).join(' ');
const NS = 'AGENTS.JORNADA.PAGINA.BLOCO_ONDE';
const CLARA = {
  name: '5511944547873',
  occupied_by: { kind: 'agent', agent_id: 21, agent_name: 'Clara' },
};

describe('resumoOnde', () => {
  it('says where it answers first and where it receives', () => {
    expect(
      resumoOnde(t, {
        primeiro: 'HUBBER COMUNIDADE',
        quantosPrimeiro: 1,
        recebe: [CLARA],
        quando: 'sempre',
      })
    ).toContain(`${NS}.PRIMEIRO_E_RECEBE`);
    expect(
      resumoOnde(t, { quantosPrimeiro: 0, recebe: [CLARA], quando: 'sempre' })
    ).toContain(`${NS}.RECEBE`);
    expect(resumoOnde(t, { quantosPrimeiro: 0, quando: 'sempre' })).toContain(
      `${NS}.NENHUM_LUGAR`
    );
  });

  it('never says "answers first" for a stopped agent', () => {
    const parado = resumoOnde(t, {
      primeiro: 'HUBBER COMUNIDADE',
      quantosPrimeiro: 1,
      recebe: [CLARA],
      quando: 'sempre',
      parado: true,
    });
    expect(parado).toContain(`${NS}.PARADO`);
    expect(parado).toContain('HUBBER COMUNIDADE, 5511944547873');
    expect(parado).not.toContain('PRIMEIRO');
    expect(
      resumoOnde(t, { quantosPrimeiro: 2, quando: 'sempre', parado: true })
    ).toContain(`${NS}.PARADO_N`);
    expect(
      resumoOnde(t, { quantosPrimeiro: 0, quando: 'sempre', parado: true })
    ).toContain(`${NS}.NENHUM_LUGAR`);
  });
});
