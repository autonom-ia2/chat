import {
  ESTADO_MATERIAL,
  aguardandoRevisao,
  ehFotoDaBase,
  estadoDoMaterial,
  precisaDeVoce,
} from '../../utils/estadoDoMaterial';

// #1426 (tema 4a) — o estado real do material: Lendo → Revisando → Pronto ou Precisa de você. "Pronto" só depois de a
// revisão aprovar; o begin_ingestion! grava needs_review já no começo da leitura, e o sinal de revisão concluída é
// review.reviewed_at.
const fonte = (status, review = null) => ({
  id: 1,
  source_type: 'pdf',
  status,
  review,
});
const REVISADO = '2026-10-19T12:00:00Z';

describe('estadoDoMaterial', () => {
  it.each([
    ['pending', null, ESTADO_MATERIAL.LENDO],
    ['processing', { status: 'needs_review', reviewed_at: null }, 'lendo'],
    ['ready', { status: 'needs_review', reviewed_at: null }, 'revisando'],
    ['ready', { status: 'accepted', reviewed_at: REVISADO }, 'pronto'],
    ['ready', { status: 'needs_resend', reviewed_at: REVISADO }, 'atencao'],
    // A revisão terminou sem parecer (IA indisponível): o agente não usa o material, então não é "Pronto".
    ['ready', { status: 'needs_review', reviewed_at: REVISADO }, 'atencao'],
    ['failed', { status: 'needs_review', reviewed_at: null }, 'falha'],
    // Falha de uma releitura com o parecer anterior restaurado continua "não consegui ler".
    ['failed', { status: 'accepted', reviewed_at: REVISADO }, 'falha'],
    // Material de antes da revisão existir (sem parecer): o agente usa, é "Pronto".
    ['ready', { status: null, reviewed_at: null }, 'pronto'],
    ['ready', null, 'pronto'],
  ])('%s with review %o is %s', (status, review, esperado) => {
    expect(estadoDoMaterial(fonte(status, review))).toBe(esperado);
  });

  it('waits for the review only while it was read and the review has not landed', () => {
    expect(
      aguardandoRevisao(
        fonte('ready', { status: 'needs_review', reviewed_at: null })
      )
    ).toBe(true);
    expect(
      aguardandoRevisao(
        fonte('ready', { status: 'needs_resend', reviewed_at: REVISADO })
      )
    ).toBe(false);
    expect(aguardandoRevisao(fonte('ready', { status: null }))).toBe(false);
    expect(aguardandoRevisao(fonte('processing'))).toBe(false);
  });

  it('needs the person when the review sent it back or it could not be read', () => {
    expect(
      precisaDeVoce(
        fonte('ready', { status: 'needs_resend', reviewed_at: REVISADO })
      )
    ).toBe(true);
    expect(precisaDeVoce(fonte('failed'))).toBe(true);
    expect(
      precisaDeVoce(
        fonte('ready', { status: 'needs_review', reviewed_at: null })
      )
    ).toBe(false);
    expect(
      precisaDeVoce(
        fonte('ready', { status: 'accepted', reviewed_at: REVISADO })
      )
    ).toBe(false);
  });

  it('knows the photo of the creation', () => {
    expect(ehFotoDaBase({ source_type: 'foto' })).toBe(true);
    expect(ehFotoDaBase({ source_type: 'pdf' })).toBe(false);
  });
});
