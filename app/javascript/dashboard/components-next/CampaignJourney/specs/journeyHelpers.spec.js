import {
  columnOptions,
  columnRows,
  currentMapping,
  hasContactColumn,
  mappingWith,
  otherColumns,
} from '../columnChoice';
import {
  PHASES,
  channelSwitches,
  companiesBlock,
  peopleSummary,
  phaseOf,
  reasonTally,
} from '../audienceReview';
import {
  audienceChannels,
  channelAvailability,
  reachOn,
  savedAudienceRows,
  searchAudiences,
} from '../audienceChannels';
import {
  bindingFromSuggestion,
  buildCampaignPayload,
  coverageMapping,
  previewMessage,
  templateVariables,
  variableLabel,
} from '../templateVariables';
import { clearDraft, draftKey, loadDraft, saveDraft } from '../campaignDraft';
import { campaignsUsingAudience, createErrorKey } from '../journeyErrors';
import { accountTimeZone, scheduleToUtc } from '../scheduleTime';

const RESOLUTION = {
  targets: {
    name: { column: 0, header: 'Responsável', confident: false },
    phone: { column: 3, header: 'Celular', confident: false },
    email: { column: 1, header: 'Email comercial', confident: true },
    company: { column: null, header: null, confident: false },
  },
  columns: [
    { index: 0, header: 'Responsável', non_blank_count: 4 },
    { index: 1, header: 'Email comercial', valid_email_count: 3 },
    { index: 2, header: 'Corretora', non_blank_count: 4 },
    { index: 3, header: 'Celular', valid_phone_count: 2 },
  ],
};

const TEMPLATE = {
  id: 9,
  name: 'renovacao_auto',
  namespace: 'ns',
  category: 'MARKETING',
  language: 'pt_BR',
  components: [
    {
      type: 'BODY',
      text: 'Olá, {{1}}! O seguro do seu carro vence em {{2}}. Equipe {{3}}',
    },
  ],
};

describe('columnChoice (PRD §6.6-1, B2)', () => {
  it('reads suggested targets and counts usable values per target', () => {
    const mapping = currentMapping(RESOLUTION);
    expect(mapping).toEqual({ name: 0, phone: 3, email: 1, company: null });

    const rows = columnRows(RESOLUTION, mapping);
    expect(rows.map(row => [row.target, row.header, row.count])).toEqual([
      ['name', 'Responsável', 4],
      ['phone', 'Celular', 2],
      ['email', 'Email comercial', 3],
      ['company', null, 0],
    ]);
    expect(rows[0].uncertain).toBe(true);
    expect(rows[2].uncertain).toBe(false);
  });

  it('prefers the manual mapping once chosen', () => {
    expect(
      currentMapping({
        ...RESOLUTION,
        manual_mapping: { name: 0, phone: null, email: 1, company: 2 },
      })
    ).toEqual({ name: 0, phone: null, email: 1, company: 2 });
  });

  it('a column feeds only one target and "Não tem" clears it', () => {
    const mapping = currentMapping(RESOLUTION);
    const moved = mappingWith(mapping, 'company', '0');
    expect(moved).toEqual({ name: null, phone: 3, email: 1, company: 0 });
    expect(mapping.name).toBe(0);
    expect(mappingWith(moved, 'phone', 'none').phone).toBeNull();
  });

  it('needs a phone or an e-mail column', () => {
    expect(
      hasContactColumn({ name: 0, phone: null, email: null, company: 2 })
    ).toBe(false);
    expect(
      hasContactColumn({ name: 0, phone: null, email: 1, company: 2 })
    ).toBe(true);
  });

  it('options list every header plus "Não tem"; other columns are the unbound ones', () => {
    expect(columnOptions(RESOLUTION, 'Não tem').map(o => o.value)).toEqual([
      '0',
      '1',
      '2',
      '3',
      'none',
    ]);
    expect(
      otherColumns(
        { schema_resolution: RESOLUTION },
        currentMapping(RESOLUTION)
      )
    ).toEqual(['Corretora']);
    expect(
      otherColumns({ extra_columns: ['Vencimento'] }, currentMapping({}))
    ).toEqual(['Vencimento']);
  });
});

describe('audienceReview (B5, J5, J6, C1–C6)', () => {
  it('maps status to the page phase', () => {
    expect(phaseOf(null)).toBe(PHASES.UPLOAD);
    expect(phaseOf({ status: 'validating' })).toBe(PHASES.CHECKING);
    expect(phaseOf({ status: 'needs_column_choice' })).toBe(PHASES.REVIEW);
    expect(phaseOf({ status: 'importing' })).toBe(PHASES.SAVING);
    expect(phaseOf({ status: 'completed_with_failures' })).toBe(PHASES.DONE);
    expect(phaseOf({ status: 'failed' })).toBe(PHASES.FAILED);
  });

  it('counts ready and problem rows and tallies reasons', () => {
    const campaignImport = {
      valid_rows: 98,
      invalid_rows: 2,
      validation_summary: {
        errors: { invalid_brazilian_mobile_number: 1, missing_contact: 1 },
      },
    };
    expect(peopleSummary(campaignImport)).toEqual({ ready: 98, problems: 2 });
    expect(reasonTally(campaignImport).map(item => item.key)).toEqual([
      'INVALID_PHONE',
      'MISSING_CONTACT',
    ]);
  });

  it('J6: a channel without data is off and cannot be switched on', () => {
    expect(
      channelSwitches({
        email: { enabled: false, count: 0 },
        whatsapp: { enabled: true, count: 4 },
      })
    ).toEqual([
      { channel: 'email', count: 0, hasData: false, enabled: false },
      { channel: 'whatsapp', count: 4, hasData: true, enabled: true },
    ]);
  });

  it('companies: hidden without the feature, preview before saving, finals after', () => {
    const base = {
      status: 'ready_to_confirm',
      create_companies: true,
      schema_resolution: {
        ...RESOLUTION,
        manual_mapping: { name: 0, phone: 3, email: 1, company: 2 },
      },
      validation_summary: {
        companies: {
          available: true,
          companies_created: 1,
          companies_reused: 2,
          contacts_linked: 9,
          contacts_kept: 1,
        },
      },
    };
    expect(
      companiesBlock({
        ...base,
        validation_summary: { companies: { available: false } },
      })
    ).toBeNull();
    expect(companiesBlock(base)).toEqual({
      column: 'Corretora',
      create: true,
      preview: { created: 1, reused: 2, linked: 9, kept: 1 },
      result: null,
    });
    expect(
      companiesBlock({
        ...base,
        status: 'completed',
        create_companies: false,
        companies: { created: 1, reused: 2, contacts_linked: 8, kept: 1 },
      })
    ).toMatchObject({
      create: false,
      result: { created: 1, reused: 2, linked: 8, kept: 1 },
    });
  });
});

describe('audienceChannels (J1, J4, J5)', () => {
  const emailOnly = {
    id: 5,
    name: 'Corretoras parceiras',
    status: 'completed',
    valid_rows: 3,
    channels: {
      email: { enabled: true, count: 3 },
      whatsapp: { enabled: false, count: 0 },
    },
  };

  it('J1: only saved audiences become options', () => {
    const rows = savedAudienceRows([
      emailOnly,
      { ...emailOnly, id: 6, status: 'ready_to_confirm' },
    ]);
    expect(rows.map(row => row.id)).toEqual([5]);
    expect(rows[0].badges).toEqual([
      { channel: 'email', enabled: true, count: 3 },
    ]);
  });

  it('J4: WhatsApp channels are unavailable without mobile, and the reverse for e-mail', () => {
    const channels = audienceChannels(emailOnly);
    expect(channelAvailability('whatsapp_official', channels)).toEqual({
      available: false,
      reason: 'NO_PHONE',
    });
    expect(channelAvailability('email', channels).available).toBe(true);
    const phoneOnly = audienceChannels({ status: 'completed', valid_rows: 7 });
    expect(channelAvailability('email', phoneOnly)).toEqual({
      available: false,
      reason: 'NO_EMAIL',
    });
    expect(reachOn('whatsapp_official', phoneOnly)).toBe(7);
  });

  it('J5: a switched-off channel reaches nobody', () => {
    const channels = audienceChannels({
      channels: {
        email: { enabled: false, count: 10 },
        whatsapp: { enabled: true, count: 4 },
      },
    });
    expect(reachOn('email', channels)).toBe(0);
    expect(channelAvailability('email', channels).available).toBe(false);
  });

  it('searches by name', () => {
    const rows = savedAudienceRows([emailOnly]);
    expect(searchAudiences(rows, 'PARCEIRAS')).toHaveLength(1);
    expect(searchAudiences(rows, 'auto')).toHaveLength(0);
  });
});

describe('templateVariables (B1, B1b)', () => {
  it('lists body variables with a label taken from the template text', () => {
    expect(
      templateVariables(TEMPLATE).map(({ key, label }) => ({ key, label }))
    ).toEqual([
      { key: '1', label: 'Olá,' },
      { key: '2', label: 'O seguro do seu carro vence em' },
      { key: '3', label: 'Equipe' },
    ]);
    expect(variableLabel('Oi {{customer_name}}', 'customer_name')).toBe(
      'customer name'
    );
  });

  it('adds TEXT header and URL button variables with the keys the backend expects', () => {
    const withExtras = {
      ...TEMPLATE,
      components: [
        { type: 'HEADER', format: 'TEXT', text: 'Renovação {{1}}' },
        { type: 'BODY', text: 'Olá, {{1}}!' },
        {
          type: 'BUTTONS',
          buttons: [
            { type: 'QUICK_REPLY', text: 'Agora não' },
            { type: 'URL', text: 'Renovar', url: 'https://x.com.br/r/{{1}}' },
          ],
        },
      ],
    };
    expect(templateVariables(withExtras)).toEqual([
      { key: '1', part: 'body', variable: '1', label: 'Olá,' },
      { key: 'header.1', part: 'header', variable: '1', label: 'Renovação' },
      { key: 'button.1', part: 'button', variable: '1', label: 'Renovar' },
    ]);
    expect(
      previewMessage({
        template: withExtras,
        bindings: {
          1: { source: 'fixed', value: 'Ana' },
          'header.1': { source: 'fixed', value: 'auto' },
          'button.1': { source: 'fixed', value: 'abc' },
        },
        placeholder: () => '?',
      })
    ).toBe('Renovação auto\n\nOlá, Ana!');
  });

  it('turns suggestions into "Sugerido" bindings', () => {
    expect(
      bindingFromSuggestion({ key: '1', source: { source: 'name' } })
    ).toEqual({ source: 'contact', value: 'name', suggested: true });
    expect(
      bindingFromSuggestion({
        key: '2',
        source: { source: 'extra', column: 'Vencimento' },
      })
    ).toEqual({ source: 'column', value: 'Vencimento', suggested: true });
    expect(bindingFromSuggestion({ key: '3', source: null })).toBeNull();
  });

  it('builds the coverage mapping without fixed texts', () => {
    expect(
      coverageMapping({
        1: { source: 'contact', value: 'first_name' },
        2: { source: 'column', value: 'Vencimento' },
        3: { source: 'fixed', value: 'Hub2You' },
      })
    ).toEqual({
      1: { source: 'name' },
      2: { source: 'extra', column: 'Vencimento' },
    });
  });

  it('previews with the first contact, the default or a label', () => {
    const bindings = {
      1: { source: 'contact', value: 'first_name' },
      2: { source: 'column', value: 'Vencimento' },
      3: { source: 'fixed', value: 'Hub2You' },
    };
    const placeholder = binding => `[${binding.value}]`;
    expect(
      previewMessage({
        template: TEMPLATE,
        bindings,
        sample: {
          name: 'Mariana Costa',
          extra_values: { Vencimento: 'out/26' },
        },
        placeholder,
      })
    ).toBe(
      'Olá, Mariana! O seguro do seu carro vence em out/26. Equipe Hub2You'
    );
    expect(
      previewMessage({
        template: TEMPLATE,
        bindings,
        defaults: { 2: 'em breve' },
        placeholder,
      })
    ).toBe(
      'Olá, [first_name]! O seguro do seu carro vence em em breve. Equipe Hub2You'
    );
  });

  it('builds the campaign request of the contract (api-1005.md §4)', () => {
    const payload = buildCampaignPayload({
      audienceId: 42,
      title: ' Renovação ',
      inboxId: 7,
      scheduledAt: null,
      template: TEMPLATE,
      bindings: {
        1: { source: 'contact', value: 'first_name', suggested: true },
        2: { source: 'column', value: 'Vencimento' },
        3: { source: 'fixed', value: 'Hub2You' },
      },
      defaults: { 2: 'em breve', 1: '  ' },
    });
    expect(payload).toEqual({
      campaign_import_id: 42,
      channel: 'whatsapp_cloud',
      campaign: {
        title: 'Renovação',
        inbox_id: 7,
        scheduled_at: null,
        template_params: {
          name: 'renovacao_auto',
          namespace: 'ns',
          category: 'MARKETING',
          language: 'pt_BR',
          processed_params: { body: { 1: '', 2: '', 3: 'Hub2You' } },
        },
        variable_bindings: {
          1: { source: 'contact', value: 'first_name' },
          2: { source: 'column', value: 'Vencimento' },
          3: { source: 'fixed', value: 'Hub2You' },
        },
        variable_defaults: { 2: 'em breve' },
      },
    });
  });
});

describe('campaignDraft (J2, J3)', () => {
  const memory = () => {
    const data = {};
    return {
      getItem: key => data[key] ?? null,
      setItem: (key, value) => {
        data[key] = value;
      },
      removeItem: key => {
        delete data[key];
      },
    };
  };

  it('keeps one draft per account and clears it', () => {
    const storage = memory();
    saveDraft(1, { title: 'Renovação', audienceId: 5 }, storage);
    expect(draftKey(1)).toBe('campaignJourney:draft:1');
    expect(loadDraft(1, storage)).toMatchObject({
      title: 'Renovação',
      audienceId: 5,
      step: 1,
    });
    expect(loadDraft(2, storage)).toBeNull();
    clearDraft(1, storage);
    expect(loadDraft(1, storage)).toBeNull();
  });

  it('survives blocked storage', () => {
    const blocked = {
      getItem: () => {
        throw new Error('blocked');
      },
      setItem: () => {
        throw new Error('blocked');
      },
      removeItem: () => {
        throw new Error('blocked');
      },
    };
    expect(saveDraft(1, {}, blocked)).toBe(false);
    expect(loadDraft(1, blocked)).toBeNull();
    expect(() => clearDraft(1, blocked)).not.toThrow();
  });
});

describe('journeyErrors', () => {
  it('names the campaigns that still use an audience', () => {
    const error = {
      response: {
        data: {
          code: 'audience_in_use',
          campaigns: [{ title: 'Renovação' }, { title: 'Parcela' }],
        },
      },
    };
    expect(campaignsUsingAudience(error)).toEqual(['Renovação', 'Parcela']);
    expect(campaignsUsingAudience({ response: { data: {} } })).toEqual([]);
  });

  it('maps every create error code to a readable message key', () => {
    const withCode = (status, code) => ({
      response: { status, data: { code } },
    });
    expect(createErrorKey(withCode(422, 'whatsapp_cloud_required'))).toBe(
      'WHATSAPP_CLOUD_REQUIRED'
    );
    expect(createErrorKey(withCode(422, 'channel_not_in_audience'))).toBe(
      'CHANNEL_NOT_IN_AUDIENCE'
    );
    expect(createErrorKey(withCode(422, 'audience_not_ready'))).toBe(
      'AUDIENCE_NOT_READY'
    );
    expect(createErrorKey(withCode(422, 'invalid_variable_bindings'))).toBe(
      'INVALID_VARIABLE_BINDINGS'
    );
    expect(createErrorKey(withCode(422, 'invalid_campaign'))).toBe(
      'INVALID_CAMPAIGN'
    );
    expect(createErrorKey(withCode(404, 'campaign_journey_disabled'))).toBe(
      'JOURNEY_DISABLED'
    );
    expect(createErrorKey(withCode(401))).toBe('NOT_ALLOWED');
    expect(createErrorKey(withCode(404))).toBe('GENERIC');
  });
});

describe('scheduleTime (PRD §6.4)', () => {
  it('reads date and time in the account zone and sends UTC', () => {
    expect(scheduleToUtc('2026-10-06T09:00', 'America/Sao_Paulo')).toBe(
      '2026-10-06T12:00:00.000Z'
    );
    expect(scheduleToUtc('', 'America/Sao_Paulo')).toBeNull();
    expect(accountTimeZone({ timezone: 'America/Cuiaba' })).toBe(
      'America/Cuiaba'
    );
    expect(accountTimeZone({ timezone: 'Not/AZone' })).toBe('UTC');
  });
});
