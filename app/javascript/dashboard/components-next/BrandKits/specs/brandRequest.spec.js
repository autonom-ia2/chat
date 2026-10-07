import BrandKitsAPI from 'dashboard/api/brandKits';
import { brandRequest, uniqueKitName } from '../brandRequest';

vi.mock('dashboard/api/brandKits', () => ({ default: { save: vi.fn() } }));

const proposal = {
  name: 'Aurora',
  source_url: 'https://aurora.example/',
  appearance: { palettes: {} },
  logo_candidates: [{ url: 'https://aurora.example/logo.png' }],
};
const savedKit = (id, warnings = []) =>
  Promise.resolve({ data: { payload: { id, name: 'Aurora' }, warnings } });

describe('identity sent by "Criar com IA" (#1076)', () => {
  beforeEach(() => {
    BrandKitsAPI.save.mockReset();
  });

  it('sends nothing but the version for the default identity', async () => {
    expect(await brandRequest({ mode: 'light' })).toEqual({
      brand: { brand_mode: 'light' },
      saved: null,
      saveFailed: false,
    });
  });

  it('sends the chosen identity', async () => {
    const { brand } = await brandRequest({ kitId: 7, mode: 'dark' });
    expect(brand).toEqual({ brand_kit_id: 7, brand_mode: 'dark' });
  });

  it('uses another site only for this e-mail when "Salvar como identidade" is not ticked', async () => {
    const result = await brandRequest({
      importId: 9,
      proposal,
      mode: 'light',
      saveAsKit: false,
    });

    expect(result.brand).toEqual({ brand_import_id: 9, brand_mode: 'light' });
    expect(BrandKitsAPI.save).not.toHaveBeenCalled();
  });

  it('ticked: saves the site as a new identity (server downloads the logo) and uses it', async () => {
    BrandKitsAPI.save.mockReturnValue(savedKit(42));

    const result = await brandRequest(
      { importId: 9, proposal, mode: 'light', saveAsKit: true },
      { takenNames: ['Hub2You'] }
    );

    expect(BrandKitsAPI.save).toHaveBeenCalledWith(null, {
      name: 'Aurora',
      source_url: 'https://aurora.example/',
      appearance: { palettes: {} },
      logo_source_url: 'https://aurora.example/logo.png',
    });
    expect(result).toEqual({
      brand: { brand_kit_id: 42, brand_mode: 'light' },
      saved: { name: 'Aurora', withoutLogo: false },
      saveFailed: false,
    });
  });

  it('ticked with a name already on the list: saves under a free name', async () => {
    BrandKitsAPI.save.mockReturnValue(savedKit(43));

    const result = await brandRequest(
      { importId: 9, proposal, mode: 'light', saveAsKit: true },
      { takenNames: ['aurora', 'Aurora 2'] }
    );

    expect(BrandKitsAPI.save.mock.calls[0][1].name).toBe('Aurora 3');
    expect(result.saved.name).toBe('Aurora 3');
  });

  it('ticked but the logo could not be stored: saved without logo, and says so', async () => {
    BrandKitsAPI.save.mockReturnValue(savedKit(44, ['logo_unsupported_type']));

    const result = await brandRequest({
      importId: 9,
      proposal,
      mode: 'dark',
      saveAsKit: true,
    });

    expect(result.saved).toEqual({ name: 'Aurora', withoutLogo: true });
  });

  it('ticked but saving fails: the e-mail still uses the site and the failure is reported', async () => {
    BrandKitsAPI.save.mockImplementation(() =>
      Promise.reject(new Error('422'))
    );

    const result = await brandRequest({
      importId: 9,
      proposal,
      mode: 'light',
      saveAsKit: true,
    });

    expect(result).toEqual({
      brand: { brand_import_id: 9, brand_mode: 'light' },
      saved: null,
      saveFailed: true,
    });
  });

  it('builds free names case-insensitively and within the name limit', () => {
    expect(uniqueKitName('Hub2You', [])).toBe('Hub2You');
    expect(uniqueKitName('Hub2You', ['HUB2YOU'])).toBe('Hub2You 2');
    expect(uniqueKitName('', [])).toBe('Identidade');
    expect(
      uniqueKitName('x'.repeat(90), ['x'.repeat(80)]).length
    ).toBeLessThanOrEqual(80);
  });
});
