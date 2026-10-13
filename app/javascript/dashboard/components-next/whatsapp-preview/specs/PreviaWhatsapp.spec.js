import { mount } from '@vue/test-utils';
import PreviaWhatsapp from '../PreviaWhatsapp.vue';

// #1459 — os quatro estados da prévia reutilizável: balão, fantasma, aviso
// tracejado e a linha de cabeçalho.
const montar = (props = {}, slots = {}) =>
  mount(PreviaWhatsapp, {
    props,
    slots,
    global: { mocks: { $t: chave => chave } },
  });

const tem = (wrapper, parte) => wrapper.find(`[data-previa-${parte}]`).exists();

describe('PreviaWhatsapp', () => {
  it('mostra o balão da empresa com o texto, o remetente e a hora', () => {
    const wrapper = montar({
      texto: 'Oi, Ana!\nTudo bem?',
      nomeDoRemetente: 'Loja',
    });

    const balao = wrapper.find('[data-previa-balao]');
    expect(balao.text()).toContain('Oi, Ana!\nTudo bem?');
    expect(balao.text()).toContain('NOVA_CONVERSA.PREVIA.AGORA');
    expect(wrapper.find('[data-previa-remetente]').text()).toBe('Loja');
    expect(tem(wrapper, 'fantasma')).toBe(false);
    expect(tem(wrapper, 'aviso')).toBe(false);
  });

  it('usa a hora recebida no lugar de "agora"', () => {
    const wrapper = montar({ texto: 'Oi', hora: '9h' });

    expect(wrapper.find('[data-previa-balao]').text()).toContain('9h');
    expect(wrapper.text()).not.toContain('NOVA_CONVERSA.PREVIA.AGORA');
  });

  it('mostra o balão fantasma, com o texto da prop, quando está vazio', () => {
    const semTexto = montar({ texto: '   ', fantasma: 'Aparece aqui' });
    const forcado = montar({ texto: 'Oi', vazio: true, fantasma: 'Aqui' });

    expect(semTexto.find('[data-previa-fantasma]').text()).toBe('Aparece aqui');
    expect(tem(semTexto, 'balao')).toBe(false);
    expect(forcado.find('[data-previa-fantasma]').text()).toBe('Aqui');
    expect(tem(forcado, 'balao')).toBe(false);
  });

  it('mostra o aviso tracejado, por prop ou slot, no lugar dos balões', () => {
    const porProp = montar({ aviso: 'Sai a mensagem pronta "Boas vindas"' });
    const porSlot = montar({ texto: 'Oi' }, { aviso: '<b>Sai a pronta</b>' });

    const aviso = porProp.find('[data-previa-aviso]');
    expect(aviso.text()).toBe('Sai a mensagem pronta "Boas vindas"');
    expect(aviso.classes()).toContain('border-dashed');
    expect(tem(porProp, 'fantasma')).toBe(false);
    expect(porSlot.find('[data-previa-aviso] b').text()).toBe('Sai a pronta');
    expect(tem(porSlot, 'balao')).toBe(false);
  });

  it('mostra a linha de cabeçalho só quando o slot vem', () => {
    const sem = montar({ texto: 'Oi' });
    const com = montar({ texto: 'Oi' }, { cabecalho: 'Vai para Mariana' });

    expect(tem(sem, 'cabecalho')).toBe(false);
    expect(com.find('[data-previa-cabecalho]').text()).toBe('Vai para Mariana');
    expect(tem(com, 'balao')).toBe(true);
  });
});
