import { perfilComCategoriaEspecial } from '../anuncioNovo';

// #2564: o aviso do perfil com seguro ou crédito é só do anúncio novo. O post impulsionado não tem a pergunta do
// destino, então o aviso (e o "Escolher outro destino") não pode aparecer nele.
describe('perfilComCategoriaEspecial', () => {
  const profile = {
    kind: 'ad',
    destination: 'INSTAGRAM_PROFILE',
    special_category: true,
  };

  it('blocks a new profile ad marked as insurance or credit', () => {
    expect(perfilComCategoriaEspecial(profile)).toBe(true);
  });

  it('never blocks a boosted post, even with the profile left in the draft', () => {
    expect(perfilComCategoriaEspecial({ ...profile, kind: 'post' })).toBe(
      false
    );
  });

  it('does not block other destinations or an unmarked profile ad', () => {
    expect(
      perfilComCategoriaEspecial({ ...profile, destination: 'WEBSITE' })
    ).toBe(false);
    expect(
      perfilComCategoriaEspecial({ ...profile, special_category: false })
    ).toBe(false);
  });
});
