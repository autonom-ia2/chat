import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import CaixaIcone from '../components/CaixaIcone.vue';

// #2255 — a caixa API ligada ao WAHA é o WhatsApp do celular: leva o ícone do WhatsApp.
const caixas = {
  5: { id: 5, channelType: 'Channel::Api', wahaProvider: true },
  6: { id: 6, channelType: 'Channel::Api', wahaProvider: false },
};
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => id => caixas[id] || {}),
}));

const icone = props => mount(CaixaIcone, { props }).find('span span');

describe('CaixaIcone', () => {
  it('mostra o WhatsApp para a caixa do WhatsApp do celular', () => {
    expect(icone({ canal: 'Channel::Api', caixaId: 5 }).classes()).toContain(
      'i-ri-whatsapp-line'
    );
  });

  it('mantém o ícone de API para a caixa API comum', () => {
    expect(icone({ canal: 'Channel::Api', caixaId: 6 }).classes()).toContain(
      'i-lucide-plug'
    );
  });

  it('sem a caixa na store, usa o canal recebido', () => {
    expect(icone({ canal: 'Channel::Email', caixaId: 99 }).classes()).toContain(
      'i-lucide-mail'
    );
    expect(icone({ canal: 'Channel::Whatsapp' }).classes()).toContain(
      'i-ri-whatsapp-line'
    );
  });
});
