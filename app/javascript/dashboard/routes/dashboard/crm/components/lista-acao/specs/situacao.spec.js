import { diasAte, situacaoDoCard, tomDoRetorno } from '../situacao';

// Meio-dia de 28/10 em São Paulo (UTC-3).
const FUSO = 'America/Sao_Paulo';
const AGORA = new Date('2026-10-28T15:00:00Z');
const contexto = {
  agora: AGORA,
  fuso: FUSO,
  locale: 'pt_BR',
  rotuloDoStatus: status =>
    ({ won: 'Seguro ativo', lost: 'Não fechou' })[status],
};

const card = mudancas => ({ id: 1, status: 'open', ...mudancas });
const retorno = dueAt =>
  card({
    action_group: 'retorno',
    next_follow_up_id: 5,
    next_follow_up_due_at: dueAt,
  });

describe('cores do retorno (decisão 3, no fuso da conta)', () => {
  it('retorno de hoje mais tarde: âmbar desde a manhã', () => {
    const tarde = retorno('2026-10-28T19:00:00Z'); // 16h em SP
    expect(tomDoRetorno(tarde, AGORA)).toBe('ambar');
    expect(situacaoDoCard(tarde, contexto)).toMatchObject({
      chave: 'SITUACAO.RETORNO_HOJE',
      valores: { hora: '16:00' },
      tom: 'ambar',
    });
  });

  it('retorno de hoje que já passou da hora: vermelho', () => {
    const manha = retorno('2026-10-28T12:00:00Z'); // 9h em SP
    expect(tomDoRetorno(manha, AGORA)).toBe('vermelho');
    expect(situacaoDoCard(manha, contexto)).toMatchObject({
      chave: 'SITUACAO.RETORNO_VENCEU_HOJE',
      valores: { hora: '09:00' },
      tom: 'vermelho',
    });
  });

  it('retorno de ontem e de dias atrás: vermelho, dizendo quando venceu', () => {
    expect(
      situacaoDoCard(retorno('2026-10-27T20:00:00Z'), contexto)
    ).toMatchObject({
      chave: 'SITUACAO.RETORNO_VENCEU_ONTEM',
      tom: 'vermelho',
    });
    expect(
      situacaoDoCard(retorno('2026-10-24T20:00:00Z'), contexto)
    ).toMatchObject({
      chave: 'SITUACAO.RETORNO_VENCEU_HA_DIAS',
      valores: { n: 4 },
      tom: 'vermelho',
    });
  });

  it('"hoje" é o dia do fuso da conta, não o do UTC', () => {
    // 01:30 UTC de 29/10 ainda é 28/10 (22:30) em São Paulo.
    expect(diasAte(new Date('2026-10-29T01:30:00Z'), AGORA, FUSO)).toBe(0);
    expect(diasAte(new Date('2026-10-28T02:30:00Z'), AGORA, FUSO)).toBe(1);
  });
});

describe('situação dos outros grupos', () => {
  it('Esperando: há quanto tempo, pelo waiting_since da conversa', () => {
    const esperando = card({
      action_group: 'esperando',
      conversation: { waiting_since: AGORA.getTime() / 1000 - 2 * 3600 },
    });
    expect(situacaoDoCard(esperando, contexto)).toMatchObject({
      chave: 'SITUACAO.ESPERANDO_DESDE.HA_HORAS',
      valores: { n: 2 },
      tom: 'azul',
    });
  });

  it('Parados: dias desde a última mensagem ou mudança de etapa', () => {
    const parado = card({
      action_group: 'parado',
      last_message_at: '2026-10-14T15:00:00Z',
      entered_stage_at: '2026-10-10T15:00:00Z',
    });
    expect(situacaoDoCard(parado, contexto)).toMatchObject({
      chave: 'SITUACAO.PARADO_HA_DIAS',
      valores: { n: 14 },
    });
  });

  it('Os demais: o retorno da pessoa antes da mensagem automática', () => {
    expect(
      situacaoDoCard(
        card({
          action_group: 'demais',
          next_follow_up_due_at: '2026-10-29T12:00:00Z',
          next_follow_up_at: '2026-10-28T18:00:00Z',
        }),
        contexto
      )
    ).toMatchObject({
      chave: 'SITUACAO.RETORNO_EM.AMANHA',
      valores: { hora: '09:00' },
    });
  });

  it('Os demais: sem retorno da pessoa, a mensagem programada ou o assistente (sem "Feito")', () => {
    const programada = card({
      action_group: 'demais',
      next_follow_up_at: '2026-10-28T19:00:00Z',
      next_follow_up_source: 'manual',
    });
    expect(situacaoDoCard(programada, contexto).chave).toBe(
      'SITUACAO.MENSAGEM_PROGRAMADA.HOJE'
    );
    expect(
      situacaoDoCard({ ...programada, next_follow_up_source: 'ai' }, contexto)
        .chave
    ).toBe('SITUACAO.ASSISTENTE_RETOMA.HOJE');
  });

  it('conversa que a pessoa não vê: "Outra pessoa está conversando", sem nome', () => {
    expect(
      situacaoDoCard(
        card({ action_group: 'demais', conversation_hidden: true }),
        contexto
      )
    ).toMatchObject({ chave: 'SITUACAO.OUTRA_PESSOA', valores: {} });
  });

  it('fechados: o nome do desfecho do funil e o motivo da perda', () => {
    expect(situacaoDoCard(card({ status: 'won' }), contexto)).toMatchObject({
      chave: 'SITUACAO.FECHADO',
      valores: { rotulo: 'Seguro ativo' },
    });
    expect(
      situacaoDoCard(card({ status: 'lost', lost_reason: 'preço' }), contexto)
    ).toMatchObject({
      chave: 'SITUACAO.FECHADO_COM_MOTIVO',
      valores: { rotulo: 'Não fechou', motivo: 'preço' },
    });
  });
});
