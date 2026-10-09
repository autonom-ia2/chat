/* global axios */
import Reports from '../emailCampaignReports';
import Campaigns from '../emailCampaigns';

describe('email protection API contract', () => {
  beforeEach(() => {
    global.axios = { get: vi.fn(), post: vi.fn() };
  });
  it('combines server recipient filters and exports the same selection', () => {
    const signal = new AbortController().signal;
    Reports.getRecipients(7, {
      page: 3,
      search: 'ana',
      status: 'bounced',
      problem: true,
      signal,
    });
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/recipients'),
      {
        params: { page: 3, q: 'ana', status: 'bounced', problem: true },
        signal,
      }
    );
    Reports.export(7, { search: 'ana', status: 'bounced', problem: true });
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/export'),
      {
        params: { q: 'ana', status: 'bounced', problem: true },
        responseType: 'blob',
      }
    );
  });
  it('loads and exports import issues through dedicated endpoints', () => {
    const signal = new AbortController().signal;
    Reports.getImportIssues(7, { page: 2, signal });
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/import_issues'),
      { params: { page: 2 }, signal }
    );
    Reports.exportImportIssues(7);
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/import_issues/export'),
      { responseType: 'blob' }
    );
  });
  it('supports independent campaign status filters and action endpoints', () => {
    const signal = new AbortController().signal;
    Reports.getReports(7, { campaignStatus: 'paused', signal });
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/reports'),
      {
        params: { campaign_id: 7, campaign_status: 'paused' },
        signal,
      }
    );
    Campaigns.get({ status: 'attention', signal });
    expect(axios.get).toHaveBeenLastCalledWith(
      expect.stringContaining('/campaigns'),
      { params: { status: 'attention' }, signal }
    );
    Campaigns.reevaluate(7);
    expect(axios.post).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/reevaluate')
    );
    Campaigns.recheck(7);
    expect(axios.post).toHaveBeenLastCalledWith(
      expect.stringContaining('/7/recheck')
    );
  });
});
