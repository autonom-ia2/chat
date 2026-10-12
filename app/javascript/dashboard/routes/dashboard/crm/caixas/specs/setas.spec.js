import { aoTeclarNoGrupo } from '../helpers/setas';

const evento = key => ({
  key,
  preventDefault: vi.fn(),
  currentTarget: { querySelector: () => null },
});

describe('aoTeclarNoGrupo', () => {
  it('moves to the next and previous option, wrapping around', () => {
    const escolher = vi.fn();
    aoTeclarNoGrupo(evento('ArrowRight'), ['a', 'b', 'c'], 'c', escolher);
    aoTeclarNoGrupo(evento('ArrowUp'), ['a', 'b', 'c'], 'a', escolher);
    expect(escolher.mock.calls).toEqual([['a'], ['c']]);
  });

  it('ignores other keys', () => {
    const escolher = vi.fn();
    const tecla = evento('Enter');
    aoTeclarNoGrupo(tecla, ['a', 'b'], 'a', escolher);
    expect(escolher).not.toHaveBeenCalled();
    expect(tecla.preventDefault).not.toHaveBeenCalled();
  });
});
