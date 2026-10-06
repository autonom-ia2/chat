import { mount } from '@vue/test-utils';
import { KeepAlive, defineComponent, h, nextTick, ref } from 'vue';
import { useOnEnter } from '../useOnEnter';

// Campaign pages sit under <keep-alive>: coming back to a page must run its setup again
// (found walking Nova campanha → Criar público → back, which showed the old empty list).
describe('useOnEnter', () => {
  it('runs on the first mount and on every return to a kept-alive page', async () => {
    const calls = [];
    // eslint-disable-next-line vue/one-component-per-file
    const Page = defineComponent({
      name: 'Page',
      setup() {
        useOnEnter(() => calls.push('enter'));
        return () => h('p', 'page');
      },
    });
    // eslint-disable-next-line vue/one-component-per-file
    const Other = defineComponent({
      name: 'Other',
      render: () => h('p', 'other'),
    });
    const current = ref(Page);
    mount({ render: () => h(KeepAlive, null, [h(current.value)]) });

    expect(calls).toEqual(['enter']);
    current.value = Other;
    await nextTick();
    current.value = Page;
    await nextTick();

    expect(calls).toEqual(['enter', 'enter']);
  });
});
