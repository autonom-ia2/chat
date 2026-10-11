import {
  caixaDaFoto,
  fotoDoAgente,
  usaFotoDoCanal,
} from '../../utils/fotoDoCanal';

// O cliente vê o agente externo com a foto do canal conectado. O interno (copiloto da equipe) e a
// cotação continuam com a foto própria.
const CAIXAS = [
  { id: 1, name: 'WhatsApp do Centro', avatar_url: 'https://x/whats.png' },
  { id: 2, name: 'Instagram', avatar_url: 'https://x/insta.png' },
  { id: 3, name: 'E-mail', avatar_url: '' },
];
const canal = (inboxId, name) => ({
  inbox_id: inboxId,
  name,
  occupied_by: { kind: 'agent', agent_id: 7 },
});
const externo = (extra = {}) => ({
  id: 7,
  actuation: 'external',
  agent_type: 'support',
  avatar_url: 'https://x/propria.png',
  ...extra,
});

describe('foto do canal', () => {
  it('uses the channel photo only for the external agent', () => {
    expect(usaFotoDoCanal(externo())).toBe(true);
    expect(usaFotoDoCanal(externo({ actuation: undefined }))).toBe(true);
    expect(usaFotoDoCanal(externo({ actuation: 'internal' }))).toBe(false);
    expect(usaFotoDoCanal(externo({ agent_type: 'insurance_quote' }))).toBe(
      false
    );
  });

  it('shows the photo of the connected inbox to the external agent', () => {
    const canais = [canal(1, 'WhatsApp do Centro')];
    expect(caixaDaFoto(externo(), canais, CAIXAS)).toEqual({
      nome: 'WhatsApp do Centro',
      foto: 'https://x/whats.png',
    });
    expect(fotoDoAgente(externo(), canais, CAIXAS)).toBe('https://x/whats.png');
  });

  it('takes the first inbox, in the order of "Answers on…", when there is more than one', () => {
    const canais = [canal(2, 'Instagram'), canal(1, 'WhatsApp do Centro')];
    expect(caixaDaFoto(externo(), canais, CAIXAS).nome).toBe('Instagram');
    expect(fotoDoAgente(externo(), canais, CAIXAS)).toBe('https://x/insta.png');
  });

  it('falls back to the agent photo, then to nothing, when the inbox has no photo', () => {
    const canais = [canal(3, 'E-mail')];
    expect(caixaDaFoto(externo(), canais, CAIXAS)).toEqual({
      nome: 'E-mail',
      foto: '',
    });
    expect(fotoDoAgente(externo(), canais, CAIXAS)).toBe(
      'https://x/propria.png'
    );
    expect(fotoDoAgente(externo({ avatar_url: null }), canais, CAIXAS)).toBe(
      ''
    );
  });

  it('falls back to the agent photo without an inbox or without the inbox in the store', () => {
    expect(caixaDaFoto(externo(), [], CAIXAS)).toBeNull();
    expect(caixaDaFoto(externo(), null, CAIXAS)).toBeNull();
    expect(fotoDoAgente(externo(), null, CAIXAS)).toBe('https://x/propria.png');
    const semCaixa = [canal(99, 'Telegram')];
    expect(caixaDaFoto(externo(), semCaixa, CAIXAS)).toEqual({
      nome: 'Telegram',
      foto: '',
    });
    expect(fotoDoAgente(externo(), semCaixa, null)).toBe(
      'https://x/propria.png'
    );
  });

  it('keeps the own photo for the internal and the quoting agent', () => {
    const canais = [canal(1, 'WhatsApp do Centro')];
    const interno = externo({ actuation: 'internal' });
    const cotacao = externo({ agent_type: 'insurance_quote' });
    expect(caixaDaFoto(interno, canais, CAIXAS)).toBeNull();
    expect(fotoDoAgente(interno, canais, CAIXAS)).toBe('https://x/propria.png');
    expect(caixaDaFoto(cotacao, canais, CAIXAS)).toBeNull();
    expect(fotoDoAgente(cotacao, canais, CAIXAS)).toBe('https://x/propria.png');
  });
});
