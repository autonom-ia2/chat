import { mount } from '@vue/test-utils';
import CampoAusenteAte from '../CampoAusenteAte.vue';
import { paraCampo, paraEnvio } from '../ausencia';

// #2414 G23 (#2737) — o "ausente até": o campo mostra a hora local e manda o instante em ISO; vazio limpa.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

describe('ausencia.js', () => {
  it('ida e volta entre a API e o campo mantém o instante', () => {
    const iso = new Date(2026, 10, 20, 18, 30).toISOString();
    expect(paraCampo(iso)).toBe('2026-11-20T18:30');
    expect(paraEnvio('2026-11-20T18:30')).toBe(iso);
  });

  it('vazio ou inválido vira vazio no campo e null no envio', () => {
    expect(paraCampo(null)).toBe('');
    expect(paraCampo('não é data')).toBe('');
    expect(paraEnvio('')).toBeNull();
  });
});

describe('CampoAusenteAte', () => {
  const montar = modelValue =>
    mount(CampoAusenteAte, { props: { modelValue } });

  it('mudar a data manda o ISO; "não está ausente" manda null', async () => {
    const tela = montar(new Date(2026, 10, 20, 18, 0).toISOString());

    tela
      .findComponent('[data-ausente-ate]')
      .vm.$emit('update:modelValue', '2026-11-22T09:00');
    expect(tela.emitted('update:modelValue').at(-1)).toEqual([
      new Date(2026, 10, 22, 9, 0).toISOString(),
    ]);

    await tela.find('[data-ausente-limpar]').trigger('click');
    expect(tela.emitted('update:modelValue').at(-1)).toEqual([null]);
  });

  it('data pela metade (vazio do navegador) não apaga a ausência', () => {
    const tela = montar(new Date(2026, 10, 20, 18, 0).toISOString());

    tela.findComponent('[data-ausente-ate]').vm.$emit('update:modelValue', '');

    expect(tela.emitted('update:modelValue')).toBeUndefined();
  });

  it('sem ausência, não mostra o botão de limpar', () => {
    expect(montar(null).find('[data-ausente-limpar]').exists()).toBe(false);
  });
});
