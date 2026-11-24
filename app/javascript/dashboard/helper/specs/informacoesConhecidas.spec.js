import {
  INFORMACOES_CONHECIDAS,
  informacoesConhecidas,
  rotuloConhecido,
} from '../informacoesConhecidas';

// #3176 — a informação sem definição de campo com chave que a plataforma
// conhece ganha nome em português, igual na ficha e no painel da conversa.
describe('informações conhecidas', () => {
  it('o cargo e a nota e as avaliações no Google, e só eles', () => {
    expect(Object.keys(INFORMACOES_CONHECIDAS)).toEqual([
      'job_title',
      'autonomia_prospecting_rating',
      'autonomia_prospecting_reviews_count',
    ]);
    expect(Object.isFrozen(INFORMACOES_CONHECIDAS)).toBe(true);
  });

  it('dá a chave i18n só da chave conhecida, inteira', () => {
    expect(rotuloConhecido('job_title')).toBe(
      'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.CARGO'
    );
    expect(rotuloConhecido('autonomia_prospecting_rating')).toBe(
      'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.NOTA_NO_GOOGLE'
    );
    expect(rotuloConhecido('job_title_2')).toBeUndefined();
    expect(rotuloConhecido('constructor')).toBeUndefined();
    expect(rotuloConhecido(undefined)).toBeUndefined();
  });

  it('lista as que o contato tem, sem as que a conta definiu como campo', () => {
    const valores = {
      job_title: 'Gerente',
      autonomia_prospecting_rating: 4.7,
      autonomia_prospecting_reviews_count: 0,
      autonomia_prospecting_lead_id: 12,
      melhor_horario: 'Tarde',
    };

    expect(informacoesConhecidas(valores)).toEqual([
      {
        chave: 'job_title',
        rotulo: 'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.CARGO',
        valor: 'Gerente',
      },
      {
        chave: 'autonomia_prospecting_rating',
        rotulo: 'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.NOTA_NO_GOOGLE',
        valor: 4.7,
      },
      {
        chave: 'autonomia_prospecting_reviews_count',
        rotulo: 'RELACIONAMENTOS_FICHA.CAMPOS.CONHECIDOS.AVALIACOES_NO_GOOGLE',
        valor: 0,
      },
    ]);
    expect(
      informacoesConhecidas(valores, ['job_title']).map(i => i.chave)
    ).toEqual([
      'autonomia_prospecting_rating',
      'autonomia_prospecting_reviews_count',
    ]);
  });

  it('vazio não é informação', () => {
    expect(informacoesConhecidas({ job_title: '' })).toEqual([]);
    expect(informacoesConhecidas({ job_title: null })).toEqual([]);
    expect(informacoesConhecidas()).toEqual([]);
  });
});
