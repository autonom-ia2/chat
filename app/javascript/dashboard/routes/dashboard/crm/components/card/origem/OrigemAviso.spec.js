import { mount } from '@vue/test-utils';
import OrigemAviso from './OrigemAviso.vue';

const A = 'CRM_CARD.ORIGEM.AVISO_ESTADO';
const render = conversao => mount(OrigemAviso, { props: { conversao } });

describe('OrigemAviso', () => {
  it('says the Facebook did not accept a refused notice', () => {
    const wrapper = render({ status: 'error', error_message: 'bad' });

    expect(wrapper.text()).toContain(`${A}.RECUSADO`);
    expect(wrapper.text()).toContain(`${A}.RECUSADO_DICA`);
  });

  // #2738: Meta may have received it; sending again could count the sale twice.
  it('says we do not know if it arrived and did not send it again', () => {
    const wrapper = render({
      status: 'error',
      error_message: 'unknown_outcome',
    });

    expect(wrapper.text()).toContain(`${A}.SEM_CONFIRMACAO`);
    expect(wrapper.text()).toContain(`${A}.SEM_CONFIRMACAO_DICA`);
    expect(wrapper.text()).not.toContain(`${A}.RECUSADO_DICA`);
    expect(wrapper.text()).not.toContain(`${A}.VER_MOTIVO`);
  });
});
