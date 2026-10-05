import { mount } from '@vue/test-utils';
import CrmCardLeadForm from './CrmCardLeadForm.vue';

const leadForm = {
  link_code: 'AB3CDE',
  captured_at: new Date().toISOString(),
  fields: [
    { key: 'destination', label: 'Destino', value: 'América do Norte - EUA' },
    { key: 'ages', label: 'Idades', value: '72' },
    { key: 'notes', label: 'Observações', value: '   ' },
    { key: 'trip_start', label: '', value: '12/10/2026' },
  ],
};

describe('CrmCardLeadForm', () => {
  it('lists each answered field as label and value, as typed in the form', () => {
    const wrapper = mount(CrmCardLeadForm, { props: { leadForm } });
    const pairs = wrapper
      .findAll('dl > div')
      .map(row => [row.get('dt').text(), row.get('dd').text()]);

    expect(wrapper.text()).toContain('CRM_KANBAN.DRAWER.LEAD_FORM_TITLE');
    expect(pairs).toEqual([
      ['Destino', 'América do Norte - EUA'],
      ['Idades', '72'],
      ['trip_start', '12/10/2026'],
    ]);
  });

  it('renders nothing without answered fields', () => {
    const wrapper = mount(CrmCardLeadForm, {
      props: { leadForm: { fields: [{ key: 'a', label: 'A', value: '' }] } },
    });

    expect(wrapper.find('section').exists()).toBe(false);
  });
});
