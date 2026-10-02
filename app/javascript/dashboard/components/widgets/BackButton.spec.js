import { mount } from '@vue/test-utils';
import BackButton from './BackButton.vue';

const router = { push: vi.fn(), go: vi.fn() };
vi.mock('vue-router', () => ({ useRouter: () => router }));
beforeEach(() => vi.clearAllMocks());

it('uses the injected router to go back without importing the application route graph', async () => {
  const wrapper = mount(BackButton);
  await wrapper.find('button').trigger('click');
  expect(router.go).toHaveBeenCalledWith(-1);
  expect(router.push).not.toHaveBeenCalled();
  wrapper.unmount();
});
it.each([
  '/app/accounts/1/contacts',
  { name: 'contacts_edit', params: { contactId: 42 } },
])('preserves the explicit destination %s', async backUrl => {
  const wrapper = mount(BackButton, {
    props: { backUrl, buttonLabel: 'Voltar' },
  });
  await wrapper.find('button').trigger('click');
  expect(router.push).toHaveBeenCalledWith(backUrl);
  expect(router.go).not.toHaveBeenCalled();
  expect(wrapper.text()).toBe('Voltar');
  wrapper.unmount();
});
it('keeps the compact appearance and default translated caption', () => {
  const wrapper = mount(BackButton, { props: { compact: true } });
  expect(wrapper.find('button').classes()).toContain('text-sm');
  expect(wrapper.text()).toBe('GENERAL_SETTINGS.BACK');
  wrapper.unmount();
});
