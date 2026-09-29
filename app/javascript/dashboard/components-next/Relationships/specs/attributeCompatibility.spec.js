import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, reactive } from 'vue';
import DateAttribute from 'dashboard/components-next/CustomAttributes/DateAttribute.vue';
import CheckboxAttribute from 'dashboard/components-next/CustomAttributes/CheckboxAttribute.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';
import {
  attributeDate,
  formatAttributeDate,
} from 'dashboard/helper/attributeDate';
import { attributeKey } from '../presentation';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

it.each(
  ['America/Sao_Paulo', 'Pacific/Auckland'].flatMap(timezone =>
    ['2026-09-29', '2026-09-29T00:00:00.000Z', '2026-09-29T23:00:00-03:00'].map(
      value => [timezone, value]
    )
  )
)('preserves written calendar dates in %s: %s', async (timezone, value) => {
  vi.stubEnv('TZ', timezone);
  expect(attributeDate(value)).toBe('2026-09-29');
  expect(formatAttributeDate(value)).toBe(
    new Date(2026, 8, 29, 12).toLocaleDateString()
  );
  const wrapper = mount(DateAttribute, { props: { attribute: { value } } });
  await wrapper.find('span').trigger('click');
  expect(wrapper.find('input').element.value).toBe('2026-09-29');
  await wrapper.find('input').setValue('2026-10-01');
  await wrapper.find('button').trigger('click');
  await flushPromises();
  expect(wrapper.emitted('update')[0]).toEqual(['2026-10-01']);
  wrapper.unmount();
  vi.unstubAllEnvs();
});
it('rejects invalid calendar values without exceptions', () => {
  expect(attributeDate('2026-02-30')).toBe('');
  expect(attributeDate('2026-2-02')).toBe('');
  expect(attributeDate('invalid')).toBe('');
});
it('shows zero and propagates checkbox props through the real switch without remount', async () => {
  const zero = mount(OtherAttribute, {
    props: { attribute: { value: 0, attributeDisplayType: 'number' } },
  });
  expect(zero.text()).toBe('0');
  const attribute = reactive({ value: false });
  const wrapper = mount(
    defineComponent({
      components: { CheckboxAttribute },
      setup: () => ({ attribute }),
      template: '<CheckboxAttribute :attribute="attribute" />',
    })
  );
  expect(wrapper.find('button[role="switch"]').attributes('aria-checked')).toBe(
    'false'
  );
  await wrapper.find('button[role="switch"]').trigger('click');
  expect(wrapper.findComponent(CheckboxAttribute).emitted('update')[0]).toEqual(
    [true]
  );
  attribute.value = true;
  await flushPromises();
  expect(wrapper.find('button[role="switch"]').attributes('aria-checked')).toBe(
    'true'
  );
  attribute.value = false;
  await flushPromises();
  expect(wrapper.find('button[role="switch"]').attributes('aria-checked')).toBe(
    'false'
  );
  wrapper.unmount();
  zero.unmount();
});
it('generates a creation key by explicit characters', () => {
  expect(attributeKey(' Função / Órgão 42 ')).toBe('funcao_orgao_42');
  expect(attributeKey('Cargo')).toBe('cargo');
  expect(attributeKey('🚀')).toBe('');
});
