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

describe('hasDraftWork', () => {
  it('is false for an empty draft and true once something was chosen', () => {
    expect(hasDraftWork(null)).toBe(false);
    expect(hasDraftWork(emptyDraft())).toBe(false);
    expect(hasDraftWork({ ...emptyDraft(), title: '  ' })).toBe(false);
    expect(hasDraftWork({ ...emptyDraft(), audienceId: 5 })).toBe(true);
  });
});
