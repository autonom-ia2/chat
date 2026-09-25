// Card do lead como o do Orth (#678, E2 frente E): fotos, telefone formatado
// com selo de verificado, redes, nota por modo, bairro, card clicável e selos
// de posição. Cada elemento roda nos dois modos da busca (GMN e Geral).
import { flushPromises } from '@vue/test-utils';
import {
  bakerySearch,
  buttonWithText,
  detailPanel,
  hotBreadLead,
  leadCard,
  moonLead,
  mountSearchPage,
  sunLead,
} from './support/searchPageHarness';
import { ADDRESS_SEPARATOR, linkWithText } from './support/resultsHelpers';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const SIGNAL = 'PROSPECTING.SEARCH.CARD_SIGNALS';

const mountWith = (scoreMode, leads) => {
  const search = bakerySearch({ score_mode: scoreMode });
  return mountSearchPage({
    searches: [search],
    payloads: { 11: { search, leads } },
  });
};

const chip = (card, label) =>
  card
    .findAll('.rounded-full.border')
    .find(element => element.text().trim() === label);

const chipLabels = card =>
  card.findAll('.rounded-full.border').map(element => element.text().trim());

// Sem posição no Google sobra a quarta vaga para a nota.
const ratedLead = extra =>
  sunLead({ search_rank: null, photo_count: 12, ...extra });

describe.each([
  ['gbp', 'bg-n-amber-2'],
  ['general', 'bg-n-teal-2'],
])('card do lead no modo %s', (scoreMode, topRatingTone) => {
  it('mostra os sinais na ordem do Orth, com fotos e nota do modo', async () => {
    const wrapper = await mountWith(scoreMode, [ratedLead()]);
    const card = leadCard(wrapper, 'Padaria Sol');

    expect(chipLabels(card)).toEqual([
      `${SIGNAL}.HAS_SITE`,
      `${SIGNAL}.HAS_PHONE`,
      `${SIGNAL}.PHOTOS`,
      `${SIGNAL}.RATING`,
    ]);
    expect(chip(card, `${SIGNAL}.PHOTOS`).classes()).toContain('bg-n-teal-2');
    expect(chip(card, `${SIGNAL}.RATING`).classes()).toContain(topRatingTone);
    const site = chip(card, `${SIGNAL}.HAS_SITE`);
    expect(site.element.tagName).toBe('A');
    expect(site.attributes('href')).toBe('https://sol.com.br');
  });

  it('nota abaixo de 3 é dor e abaixo de 4 é oportunidade', async () => {
    const wrapper = await mountWith(scoreMode, [
      ratedLead({ rating: 2.4 }),
      hotBreadLead({ search_rank: null, photo_count: 12, rating: 3.4 }),
    ]);

    expect(
      chip(leadCard(wrapper, 'Padaria Sol'), `${SIGNAL}.RATING`).classes()
    ).toContain('bg-n-ruby-2');
    expect(
      chip(leadCard(wrapper, 'Pão Quente'), `${SIGNAL}.RATING`).classes()
    ).toContain('bg-n-amber-2');
  });

  it('fotos: sem foto é dor e pouca foto é oportunidade', async () => {
    const wrapper = await mountWith(scoreMode, [
      sunLead({ photo_count: 0 }),
      hotBreadLead({ photo_count: 3 }),
    ]);

    expect(
      chip(leadCard(wrapper, 'Padaria Sol'), `${SIGNAL}.NO_PHOTO`).classes()
    ).toContain('bg-n-ruby-2');
    expect(
      chip(leadCard(wrapper, 'Pão Quente'), `${SIGNAL}.FEW_PHOTOS`).classes()
    ).toContain('bg-n-amber-2');
  });

  it('telefone formatado com selo de verificado só no WhatsApp confirmado', async () => {
    const wrapper = await mountWith(scoreMode, [
      sunLead(),
      hotBreadLead(),
      moonLead(),
    ]);

    const sun = leadCard(wrapper, 'Padaria Sol').find(
      '[data-test="lead-phone"]'
    );
    expect(sun.text()).toContain('+55 41 99999 0001');
    expect(sun.text()).toContain('PROSPECTING.SEARCH.WHATSAPP_VERIFIED');

    const hotBread = leadCard(wrapper, 'Pão Quente').find(
      '[data-test="lead-phone"]'
    );
    expect(hotBread.text()).toBe('+55 41 3333 0002');

    expect(
      leadCard(wrapper, 'Confeitaria Lua')
        .find('[data-test="lead-phone"]')
        .exists()
    ).toBe(false);
  });

  it('ícones de Instagram, Facebook e LinkedIn quando o lead tem o link', async () => {
    const wrapper = await mountWith(scoreMode, [
      sunLead({
        enriched_instagram: 'https://instagram.com/padariasol',
        enriched_facebook: 'facebook.com/padariasol',
        enriched_linkedin: 'https://www.linkedin.com/company/padariasol',
      }),
      hotBreadLead(),
    ]);
    const card = leadCard(wrapper, 'Padaria Sol');
    const social = network =>
      card.find(`a[aria-label="PROSPECTING.SEARCH.CARD_SOCIAL.${network}"]`);

    expect(social('INSTAGRAM').attributes('href')).toBe(
      'https://instagram.com/padariasol'
    );
    expect(social('FACEBOOK').attributes('href')).toBe(
      'https://facebook.com/padariasol'
    );
    expect(social('LINKEDIN').attributes('href')).toBe(
      'https://www.linkedin.com/company/padariasol'
    );
    expect(social('INSTAGRAM').attributes('target')).toBe('_blank');
    expect(social('INSTAGRAM').attributes('rel')).toBe('noopener noreferrer');

    expect(
      leadCard(wrapper, 'Pão Quente')
        .findAll('a[aria-label^="PROSPECTING.SEARCH.CARD_SOCIAL"]')
        .map(link => link.attributes('aria-label'))
    ).toEqual([]);
  });

  it('mostra o bairro no lugar do endereço quando o lead tem bairro', async () => {
    const wrapper = await mountWith(scoreMode, [
      sunLead({ neighborhood: 'Batel' }),
      hotBreadLead(),
    ]);

    const sun = leadCard(wrapper, 'Padaria Sol');
    expect(sun.text()).toContain('Batel');
    expect(sun.text()).not.toContain('Rua A, 10');
    expect(leadCard(wrapper, 'Pão Quente').text()).toContain(
      `Rua B, 20${ADDRESS_SEPARATOR}Curitiba PR`
    );
  });

  it('selos de posição no Google e Ligar 1º', async () => {
    const wrapper = await mountWith(scoreMode, [sunLead(), hotBreadLead()]);

    const sun = leadCard(wrapper, 'Padaria Sol');
    expect(sun.text()).toContain('PROSPECTING.SEARCH.PRIORITY_GOOGLE_RANK');
    expect(sun.text()).toContain(
      'PROSPECTING.SEARCH.PRIORITY_FIRST_CALL_SHORT'
    );
    expect(leadCard(wrapper, 'Pão Quente').text()).not.toContain(
      'PROSPECTING.SEARCH.PRIORITY_FIRST_CALL_SHORT'
    );
  });

  it('o card inteiro abre e fecha o painel, sem quebrar os botões internos', async () => {
    const wrapper = await mountWith(scoreMode, [sunLead()]);
    const card = () => leadCard(wrapper, 'Padaria Sol');

    await card().find('input[type="checkbox"]').trigger('click');
    await linkWithText(card(), 'PROSPECTING.SEARCH.WHATSAPP').trigger('click');
    await flushPromises();
    expect(detailPanel(wrapper).exists()).toBe(false);

    await card().find('h3').trigger('click');
    await flushPromises();
    expect(detailPanel(wrapper).exists()).toBe(true);
    expect(card().classes()).toContain('border-n-brand');
    expect(
      buttonWithText(card(), 'PROSPECTING.SEARCH.OPEN_DETAILS').attributes(
        'aria-expanded'
      )
    ).toBe('true');

    await card().trigger('click');
    await flushPromises();
    expect(detailPanel(wrapper).exists()).toBe(false);
    expect(card().classes()).not.toContain('border-n-brand');
  });

  it('o botão Detalhes alterna o painel', async () => {
    const wrapper = await mountWith(scoreMode, [sunLead()]);
    const details = () =>
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_DETAILS'
      );

    expect(details().attributes('aria-expanded')).toBe('false');
    await details().trigger('click');
    await flushPromises();
    expect(detailPanel(wrapper).exists()).toBe(true);
    await details().trigger('click');
    await flushPromises();
    expect(detailPanel(wrapper).exists()).toBe(false);
  });

  it('checkbox com rótulo para leitor de tela', async () => {
    const wrapper = await mountWith(scoreMode, [sunLead()]);
    const checkbox = () =>
      leadCard(wrapper, 'Padaria Sol').find('input[type="checkbox"]');

    expect(checkbox().attributes('aria-label')).toBe(
      'PROSPECTING.SEARCH.SELECT_LEAD'
    );
    await checkbox().trigger('change');
    expect(checkbox().attributes('aria-label')).toBe(
      'PROSPECTING.SEARCH.DESELECT_LEAD'
    );
  });

  it('o botão Mapa usa o link oficial do Google quando o lead tem', async () => {
    const wrapper = await mountWith(scoreMode, [
      sunLead({ google_maps_uri: 'https://maps.google.com/?cid=123' }),
      hotBreadLead(),
    ]);

    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_MAP'
      ).attributes('href')
    ).toBe('https://maps.google.com/?cid=123');
    expect(
      linkWithText(
        leadCard(wrapper, 'Pão Quente'),
        'PROSPECTING.SEARCH.OPEN_MAP'
      ).attributes('href')
    ).toContain('https://www.google.com/maps/search/?api=1&query=');
  });
});
