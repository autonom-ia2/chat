import BrandKitsAPI from 'dashboard/api/brandKits';

// Name limit of a kit (BrandKit::NAME_MAX).
const NAME_MAX = 80;
const FALLBACK_NAME = 'Identidade';

// The site name, or the site name plus " 2", " 3"... when it is already on the list (names are unique
// among the live identities, ignoring case).
export const uniqueKitName = (name, takenNames = []) => {
  const taken = new Set(takenNames.map(item => item.toLowerCase()));
  const base = (name || '').trim().slice(0, NAME_MAX - 4) || FALLBACK_NAME;
  if (!taken.has(base.toLowerCase())) return base;
  let index = 2;
  while (taken.has(`${base} ${index}`.toLowerCase())) index += 1;
  return `${base} ${index}`;
};

// "Salvar como identidade" (#1076): the site read for this e-mail becomes a kit through the same
// POST brand_kits as Nova identidade (validation and logo download on the server; not the default
// unless it is the first). -> the saved name, or null when saving failed.
const saveSiteAsKit = async (proposal, takenNames) => {
  const name = uniqueKitName(proposal.name, takenNames);
  try {
    const { data } = await BrandKitsAPI.save(null, {
      name,
      source_url: proposal.source_url,
      appearance: proposal.appearance,
      logo_source_url: proposal.logo_candidates?.[0]?.url,
    });
    const kit = data.payload || data;
    return { id: kit.id, name, withoutLogo: (data.warnings || []).length > 0 };
  } catch {
    return null;
  }
};

// What "Criar com IA" sends about the identity, from the picker's choice:
// - a site read for this e-mail, saved first as a new identity when "Salvar como identidade" is
//   ticked (if saving fails, the e-mail still uses the site and saveFailed says so);
// - a chosen identity; or nothing, and the server uses the default one.
// -> { brand: request params, saved: { name, withoutLogo } | null, saveFailed }
export const brandRequest = async (choice, { takenNames = [] } = {}) => {
  const mode = { brand_mode: choice.mode };
  const result = (brand, saved = null, saveFailed = false) => ({
    brand,
    saved,
    saveFailed,
  });
  if (choice.importId && choice.saveAsKit && choice.proposal) {
    const saved = await saveSiteAsKit(choice.proposal, takenNames);
    if (saved) {
      return result(
        { brand_kit_id: saved.id, ...mode },
        { name: saved.name, withoutLogo: saved.withoutLogo }
      );
    }
    return result({ brand_import_id: choice.importId, ...mode }, null, true);
  }
  if (choice.importId)
    return result({ brand_import_id: choice.importId, ...mode });
  if (choice.kitId) return result({ brand_kit_id: choice.kitId, ...mode });
  return result(mode);
};
