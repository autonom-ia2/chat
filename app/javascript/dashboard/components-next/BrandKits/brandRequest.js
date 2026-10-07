import BrandKitsAPI from 'dashboard/api/brandKits';

// What "Criar com IA" sends about the identity (#1076), from the picker's choice:
// - a site read for this e-mail: saved first as a new identity when "Salvar como identidade" is
//   ticked (then it is a kit like any other), otherwise sent as the reading itself;
// - a chosen identity; or nothing, and the server uses the default one.
export const brandRequest = async choice => {
  const mode = { brand_mode: choice.mode };
  if (choice.importId && choice.saveAsKit && choice.proposal) {
    const { proposal } = choice;
    const { data } = await BrandKitsAPI.save(null, {
      name: proposal.name,
      source_url: proposal.source_url,
      appearance: proposal.appearance,
      logo_source_url: proposal.logo_candidates?.[0]?.url,
    });
    return { brand_kit_id: (data.payload || data).id, ...mode };
  }
  if (choice.importId) return { brand_import_id: choice.importId, ...mode };
  if (choice.kitId) return { brand_kit_id: choice.kitId, ...mode };
  return mode;
};
