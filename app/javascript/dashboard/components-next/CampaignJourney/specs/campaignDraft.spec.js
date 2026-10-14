import { emptyDraft, hasDraftWork, journeyEntry } from '../campaignDraft';

// #1093: where Nova campanha starts is read from the address, never silently from storage.
describe('journeyEntry', () => {
  const stored = {
    ...emptyDraft(),
    title: 'Novidades',
    channel: 'email',
    emailCampaignId: 54,
    step: 2,
  };

  it('asks when there is no query and the stored draft holds work', () => {
    expect(journeyEntry({}, stored)).toEqual({ draft: null, pending: stored });
  });

  it('starts fresh when there is no query and nothing worth resuming', () => {
    expect(journeyEntry({}, null)).toEqual({ draft: emptyDraft() });
    expect(journeyEntry({}, emptyDraft())).toEqual({ draft: emptyDraft() });
  });

  it('resumes from the editor only for the same e-mail', () => {
    expect(journeyEntry({ email: '54' }, stored)).toEqual({ draft: stored });
    expect(journeyEntry({ email: '99' }, stored)).toEqual({
      draft: emptyDraft(),
    });
  });

  it('resumes on reload (?draft=1)', () => {
    expect(journeyEntry({ draft: '1' }, stored)).toEqual({ draft: stored });
    expect(journeyEntry({ draft: '1' }, null)).toEqual({ draft: emptyDraft() });
  });

  it('keeps J3 and F3: back from Novo público resumes, "Usar em nova campanha" starts fresh', () => {
    expect(journeyEntry({ returned: '1', audience: '5' }, stored)).toEqual({
      draft: { ...stored, audienceId: 5, step: 1 },
    });
    expect(journeyEntry({ audience: '5' }, stored)).toEqual({
      draft: { ...emptyDraft(), audienceId: 5, step: 1 },
    });
  });
});

// #1332: ?modelo=&caixa= (Modelos do WhatsApp) only with the flag; without it the address is the usual one.
describe('journeyEntry with a template', () => {
  const query = { modelo: '1001', caixa: '7' };

  it('ignores modelo when the templates journey is off', () => {
    expect(journeyEntry(query, null)).toEqual({ draft: emptyDraft() });
  });

  it('opens WhatsApp Oficial with the box and the template when it is on', () => {
    expect(journeyEntry(query, null, { withTemplates: true })).toEqual({
      draft: {
        ...emptyDraft(),
        channel: 'whatsapp_official',
        inboxId: 7,
        templateId: '1001',
        // #1465: outro modelo começa sem o que foi escolhido para o anterior (cupom, arquivos).
        formato: {},
        step: 1,
      },
    });
  });

  it('keeps the stored draft when coming back (returned=1)', () => {
    const stored = { ...emptyDraft(), title: 'Guardada', audienceId: 5 };
    expect(
      journeyEntry({ ...query, returned: '1' }, stored, { withTemplates: true })
        .draft
    ).toMatchObject({
      title: 'Guardada',
      audienceId: 5,
      templateId: '1001',
      step: 2,
    });
  });
});

describe('hasDraftWork', () => {
  it('is false for an empty draft and true once something was chosen', () => {
    expect(hasDraftWork(null)).toBe(false);
    expect(hasDraftWork(emptyDraft())).toBe(false);
    expect(hasDraftWork({ ...emptyDraft(), title: '  ' })).toBe(false);
    expect(hasDraftWork({ ...emptyDraft(), audienceId: 5 })).toBe(true);
  });
});
