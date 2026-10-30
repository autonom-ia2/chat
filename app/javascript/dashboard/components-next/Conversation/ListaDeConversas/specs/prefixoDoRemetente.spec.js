import { REMETENTE, prefixoDoRemetente } from '../prefixoDoRemetente';

const AGENTES = {
  7: { id: 7, name: 'Bruno Reis', available_name: 'Bruno Reis' },
  9: { id: 9, name: 'Ana Lopes', available_name: 'Ana Lopes' },
};
const contexto = { euId: 7, agentePorId: id => AGENTES[id] || {} };
const de = mensagem => prefixoDoRemetente(mensagem, contexto);

describe('prefixoDoRemetente (#2202, linha 2)', () => {
  it('cliente: sem prefixo', () => {
    expect(de({ message_type: 0, sender_type: 'Contact' })).toEqual({
      tipo: REMETENTE.CLIENTE,
    });
  });

  it('eu: "Você"; outra pessoa: o primeiro nome', () => {
    const minha = { message_type: 1, sender_type: 'User', sender: AGENTES[7] };
    const dela = { message_type: 1, sender_type: 'User', sender: AGENTES[9] };
    expect(de(minha).tipo).toBe(REMETENTE.VOCE);
    expect(de(dela)).toMatchObject({ tipo: REMETENTE.PESSOA, nome: 'Ana' });
  });

  it('robô: o nome gravado, com o selo (nunca "IA:" sozinho)', () => {
    const robo = {
      message_type: 1,
      sender_type: 'AgentBot',
      sender: { id: 3, name: 'Gabriela', type: 'agent_bot' },
    };
    expect(de(robo)).toEqual({ tipo: REMETENTE.ROBO, nome: 'Gabriela' });
  });

  it('eco do celular: o autor congelado; sem autor, "Equipe"', () => {
    const comAutor = {
      message_type: 1,
      content_attributes: { external_echo: true, c2y_phone_author_id: 9 },
    };
    const meu = {
      message_type: 1,
      content_attributes: { external_echo: true, c2y_phone_author_id: 7 },
    };
    const semAutor = {
      message_type: 1,
      content_attributes: { external_echo: true },
    };
    expect(de(comAutor)).toMatchObject({ tipo: REMETENTE.PESSOA, nome: 'Ana' });
    expect(de(meu).tipo).toBe(REMETENTE.VOCE);
    expect(de(semAutor).tipo).toBe(REMETENTE.EQUIPE);
  });

  it('modelo sem remetente: "Equipe"; nota: "Nota"', () => {
    expect(de({ message_type: 3 }).tipo).toBe(REMETENTE.EQUIPE);
    expect(
      de({
        message_type: 1,
        private: true,
        sender_type: 'User',
        sender: AGENTES[9],
      }).tipo
    ).toBe(REMETENTE.NOTA);
  });

  it('não lê o texto: "Ana: oi" vindo do cliente continua sem prefixo', () => {
    expect(de({ message_type: 0, content: 'Ana: oi' }).tipo).toBe(
      REMETENTE.CLIENTE
    );
  });
});
