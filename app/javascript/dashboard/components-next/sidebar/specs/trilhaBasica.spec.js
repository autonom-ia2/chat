import { basicoDaTrilhaConcluido, passosPendentes } from '../fork/trilhaBasica';

const passo = (id, etapa, status, pulavel = false) => ({
  id,
  etapa,
  status,
  pulavel,
});

const basicoFeito = [
  passo('perfil', 'ligar', 'feito'),
  passo('chave_ia', 'ligar', 'feito'),
  passo('canal', 'ligar', 'feito'),
  passo('primeira_resposta', 'ligar', 'feito'),
  passo('funil', 'organizar', 'feito'),
];

describe('trilhaBasica', () => {
  it('básico feito mesmo com os opcionais e a etapa crescer pendentes', () => {
    const passos = [
      ...basicoFeito,
      passo('equipe', 'organizar', 'pendente', true),
      passo('agente_ia', 'organizar', 'pendente', true),
      passo('campanha', 'crescer', 'pendente'),
    ];
    expect(basicoDaTrilhaConcluido(passos)).toBe(true);
    expect(passosPendentes(passos)).toBe(3);
  });

  it('um passo obrigatório pendente (ex.: canal desconectado) mantém o item no menu', () => {
    const passos = basicoFeito.map(p =>
      p.id === 'canal' ? { ...p, status: 'pendente' } : p
    );
    expect(basicoDaTrilhaConcluido(passos)).toBe(false);
  });

  it('sem trilha carregada não conta como concluído', () => {
    expect(basicoDaTrilhaConcluido([])).toBe(false);
  });
});
