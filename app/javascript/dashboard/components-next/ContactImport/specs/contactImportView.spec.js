import {
  NO_COLUMN,
  stageFor,
  currentMapping,
  mappingPayload,
  hasContactColumn,
  visibleTargets,
  peopleCounts,
  resultCounts,
} from '../contactImportView';

const resolution = {
  targets: {
    name: { column: 0 },
    phone: { column: 1 },
    email: { column: null },
    company: { column: 2 },
  },
  columns: [
    { index: 0, header: 'Segurado' },
    { index: 1, header: 'Fone 1' },
    { index: 2, header: 'Corretora' },
  ],
};

describe('contactImportView', () => {
  it('maps statuses to the screen stages', () => {
    expect(stageFor(null)).toBe('upload');
    expect(stageFor({ status: 'validating' })).toBe('reading');
    expect(stageFor({ status: 'needs_column_choice' })).toBe('review');
    expect(stageFor({ status: 'queued' })).toBe('importing');
    expect(stageFor({ status: 'completed_with_failures' })).toBe('done');
    expect(stageFor({ status: 'failed' })).toBe('failed');
  });

  it('uses the found columns, then the manual choice, with "Não tem" for none', () => {
    expect(currentMapping({ schema_resolution: resolution })).toEqual({
      name: 0,
      phone: 1,
      email: NO_COLUMN,
      company: 2,
    });
    const manual = {
      ...resolution,
      manual_mapping: { name: null, phone: null, email: 1, company: null },
    };
    expect(currentMapping({ schema_resolution: manual })).toEqual({
      name: NO_COLUMN,
      phone: NO_COLUMN,
      email: 1,
      company: NO_COLUMN,
    });
  });

  it('sends null for "Não tem" and requires mobile or e-mail', () => {
    const mapping = { name: 0, phone: NO_COLUMN, email: NO_COLUMN, company: 2 };
    expect(mappingPayload(mapping)).toEqual({
      name: 0,
      phone: null,
      email: null,
      company: 2,
    });
    expect(hasContactColumn(mapping)).toBe(false);
    expect(hasContactColumn({ ...mapping, email: 3 })).toBe(true);
  });

  it('hides the company row when the account has no companies (C6)', () => {
    const contactImport = {
      validation_summary: { companies: { available: false } },
    };
    expect(visibleTargets(contactImport)).toEqual(['name', 'phone', 'email']);
  });

  it('counts people before and after importing', () => {
    expect(
      peopleCounts({
        valid_rows: 98,
        invalid_rows: 5,
        validation_summary: { existing_contacts: 41 },
      })
    ).toEqual({ ready: 98, existing: 41, created: 57, problems: 5 });
    expect(
      resultCounts({
        imported_contacts_count: 98,
        existing_contacts_count: 41,
        failed_contacts_count: 1,
        invalid_rows: 5,
        companies: { created: 15 },
        validation_summary: { contact_attributes_created: 2 },
      })
    ).toEqual({
      imported: 98,
      created: 57,
      companies: 15,
      attributes: 2,
      failed: 6,
    });
  });
});
