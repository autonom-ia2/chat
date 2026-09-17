// Installed before the real page mounts. Visibility is independent of viewport
// position: scrolling must never remove an action from keyboard expectations.
export function installDomHelpers() {
  window.__qaDom = {
    isExposed(element) {
      // Visibility is inherited but may be explicitly restored on a descendant.
      if (['hidden', 'collapse'].includes(getComputedStyle(element).visibility))
        return false;
      for (
        let ancestor = element;
        ancestor;
        ancestor = ancestor.parentElement
      ) {
        const style = getComputedStyle(ancestor);
        if (
          ancestor.hidden ||
          ancestor.inert ||
          style.display === 'none' ||
          style.contentVisibility === 'hidden' ||
          style.opacity === '0'
        )
          return false;
        if (ancestor.tagName === 'DETAILS' && !ancestor.open) {
          const summary = [...ancestor.children].find(
            child => child.tagName === 'SUMMARY'
          );
          if (!summary?.contains(element)) return false;
        }
      }
      // Do not filter by viewport or geometry: zero-size actions must fail
      // the style/focus assertions instead of disappearing from expectations.
      return true;
    },
  };
}
