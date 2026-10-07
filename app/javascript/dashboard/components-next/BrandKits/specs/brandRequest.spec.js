import BrandKitsAPI from 'dashboard/api/brandKits';
import { brandRequest } from '../brandRequest';

vi.mock('dashboard/api/brandKits', () => ({
  default: { save: vi.fn(() => Promise.resolve({ data: { id: 42 } })) },
}));

const proposal = {
  name: 'Aurora',
  source_url: 'https://aurora.example/',
  appearance: { palettes: {} },
  logo_candidates: [{ url: 'https://aurora.example/logo.png' }],
};

describe('identity sent by "Criar com IA" (#1076)', () => {
  beforeEach(() => BrandKitsAPI.save.mockClear());

  it('sends nothing but the version for the default identity', async () => {
    expect(await brandRequest({ mode: 'light' })).toEqual({
      brand_mode: 'light',
    });
  });

  it('sends the chosen identity', async () => {
    expect(await brandRequest({ kitId: 7, mode: 'dark' })).toEqual({
      brand_kit_id: 7,
      brand_mode: 'dark',
    });
  });

  it('uses another site only for this e-mail when not saved', async () => {
    expect(
      await brandRequest({
        importId: 9,
        proposal,
        mode: 'light',
        saveAsKit: false,
      })
    ).toEqual({ brand_import_id: 9, brand_mode: 'light' });
    expect(BrandKitsAPI.save).not.toHaveBeenCalled();
  });

  it('saves the site as a new identity first when "Salvar como identidade" is ticked', async () => {
    const request = await brandRequest({
      importId: 9,
      proposal,
      mode: 'light',
      saveAsKit: true,
    });

    expect(BrandKitsAPI.save).toHaveBeenCalledWith(null, {
      name: 'Aurora',
      source_url: 'https://aurora.example/',
      appearance: { palettes: {} },
      logo_source_url: 'https://aurora.example/logo.png',
    });
    expect(request).toEqual({ brand_kit_id: 42, brand_mode: 'light' });
  });
});
