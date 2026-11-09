import { mount } from '@vue/test-utils';
import AcharFraseCampo from '../components/AcharFraseCampo.vue';

// #2696 — a resposta da IA que nunca chega não deixa a porta travada: depois
// do prazo, o aviso de falha aparece e "ocupado" volta a falso.
describe('AcharFraseCampo: prazo', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('a promessa que nunca resolve vira o aviso de falha e destrava', async () => {
    const wrapper = mount(AcharFraseCampo, {
      props: { interpretar: () => new Promise(() => {}) },
    });
    await wrapper.find('[data-campo-frase]').setValue('padarias no centro');

    await wrapper.find('[data-preencher]').trigger('click');
    expect(wrapper.emitted('update:ocupado').at(-1)).toEqual([true]);

    await vi.advanceTimersByTimeAsync(22000);

    expect(wrapper.emitted('update:ocupado').at(-1)).toEqual([false]);
    expect(wrapper.find('[data-aviso-frase]').text()).toContain(
      'PORTA.FRASE.ERRO'
    );
    expect(wrapper.emitted('entendeu')).toBeUndefined();
  });
});
