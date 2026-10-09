import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import KnowledgeMaterialCard from './KnowledgeMaterialCard.vue';

withFullI18n('pt_BR');
enableAutoUnmount(afterEach);

const material = (screen_state, extra = {}) => ({
  id: 7,
  kind: 'knowledge',
  source_type: 'pdf',
  reference: 'manual.pdf',
  screen_state,
  uses: true,
  review: {},
  ...extra,
});

const mountCard = (source, props = {}) =>
  mount(KnowledgeMaterialCard, {
    props: { source, canManage: true, ...props },
    global: {
      stubs: { Spinner: true },
    },
  });

describe('KnowledgeMaterialCard', () => {
  it.each([
    'uploading',
    'reading',
    'unreadable',
    'needs_another_file',
    'not_reviewed',
    'out_of_business_not_used',
    'out_of_business_used',
    'ready',
  ])('renderiza o estado projetado %s sem recalcular pelo status', state => {
    const wrapper = mountCard(
      material(state, { status: 'failed', review: { status: 'accepted' } })
    );

    expect(
      wrapper.get('[data-testid="knowledge-material"]').attributes('data-state')
    ).toBe(state);
  });

  it('mostra qualidade e resumo quando o material está pronto', () => {
    const wrapper = mountCard(
      material('ready', {
        review: {
          status: 'accepted',
          quality_score: 92,
          label: 'boa',
          confidence: 'alta',
          summary: 'Manual de atendimento',
        },
      })
    );

    expect(wrapper.get('[data-testid="material-quality"]').text()).toContain(
      'Nota 9,2 de 10'
    );
    expect(wrapper.text()).toContain('Manual de atendimento');
  });

  it('não apresenta nota zero quando a avaliação não tem nota', () => {
    const wrapper = mountCard(
      material('ready', { review: { quality_score: null } })
    );
    expect(
      wrapper.get('[data-testid="material-quality"]').text()
    ).not.toContain('Nota');
  });

  it('emite reenviar e remover somente pelos controles de gestão', async () => {
    const wrapper = mountCard(material('needs_another_file'), {
      canManage: true,
    });

    await wrapper.get('[data-action="resync"]').trigger('click');
    await wrapper.get('[data-action="remove"]').trigger('click');

    expect(wrapper.emitted('resync')).toEqual([[7]]);
    expect(wrapper.emitted('remove')).toEqual([[7]]);
  });

  it('não mostra ações de escrita para uma leitura sem permissão', () => {
    const wrapper = mountCard(material('needs_another_file'), {
      canManage: false,
    });

    expect(wrapper.find('[data-action="resync"]').exists()).toBe(false);
    expect(wrapper.find('[data-action="remove"]').exists()).toBe(false);
  });
});
