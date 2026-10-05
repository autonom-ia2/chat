import {
  campaignSourceIdsFromQuery,
  crmKanbanRoute,
  journeyStatus,
  messageKpis,
  percent,
  resultBalance,
  resultRoute,
  statusTabs,
} from '../resultMetrics';

describe('campaign result helpers (#1007)', () => {
  it('lists the numbers of each message channel in screen order (PRD §6.5)', () => {
    const totals = {
      audience: 4,
      sent: 2,
      delivered: 2,
      read: 1,
      replied: 1,
      failed: 1,
      skipped: 1,
    };
    const keys = channel => messageKpis(channel, totals).map(kpi => kpi.key);

    expect(keys('whatsapp_official')).toEqual([
      'audience',
      'sent',
      'delivered',
      'read',
      'replied',
      'failed',
      'skipped',
    ]);
    expect(keys('whatsapp_api')).toEqual([
      'audience',
      'sent',
      'replied',
      'failed',
      'skipped',
    ]);
    expect(keys('sms')).not.toContain('read');
    expect(messageKpis('whatsapp_official', totals)[1]).toEqual({
      key: 'sent',
      value: 2,
      rate: 50,
    });
  });

  it('E1: the situations add up to the audience, and a gap is reported', () => {
    expect(
      resultBalance('whatsapp_official', {
        audience: 4,
        sent: 2,
        failed: 1,
        skipped: 1,
        queued: 0,
      }).holds
    ).toBe(true);
    expect(
      resultBalance('email', {
        eligible: 3,
        delivered: 1,
        bounced: 1,
        not_sent: 1,
      })
    ).toEqual({
      parts: [
        { key: 'delivered', value: 1 },
        { key: 'bounced', value: 1 },
        { key: 'not_sent', value: 1 },
      ],
      total: 3,
      holds: true,
    });
    expect(
      resultBalance('sms', { audience: 3, sent: 1, failed: 1 }).holds
    ).toBe(false);
  });

  it('builds the result, Kanban and tab values', () => {
    expect(resultRoute('email', 9)).toEqual({
      name: 'campaigns_journey_result',
      params: { channel: 'email', campaignId: 9 },
    });
    expect(crmKanbanRoute('campaign:email:9')).toEqual({
      name: 'crm_kanban_index',
      query: { campaign_source_ids: 'campaign:email:9' },
    });
    expect(
      campaignSourceIdsFromQuery({
        campaign_source_ids: 'campaign:email:9, campaign:whatsapp:2',
      })
    ).toEqual(['campaign:email:9', 'campaign:whatsapp:2']);
    expect(campaignSourceIdsFromQuery({})).toEqual([]);
    expect(statusTabs(['skipped', 'sent', 'replied'])).toEqual([
      '',
      'sent',
      'replied',
      'skipped',
    ]);
    expect(percent(1, 0)).toBeNull();
    expect(journeyStatus('email', 'sent')).toBe('completed');
    expect(journeyStatus('whatsapp_api', 'running')).toBe('sending');
    expect(journeyStatus('whatsapp_official', 'processing')).toBe('sending');
  });
});
