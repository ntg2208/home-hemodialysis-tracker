import { useEffect } from 'react';

export function useKeyboardAvoidance() {
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;

    function update() {
      // offsetTop accounts for the browser chrome scrolling (e.g. address bar hiding)
      const kb = Math.max(0, window.innerHeight - vv!.height - vv!.offsetTop);
      document.documentElement.style.setProperty('--kb', `${Math.round(kb)}px`);
    }

    // When an input is focused, wait for keyboard animation then scroll it into view
    function onFocusIn(e: FocusEvent) {
      const el = e.target as HTMLElement;
      if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
        setTimeout(() => el.scrollIntoView({ block: 'nearest', behavior: 'smooth' }), 300);
      }
    }

    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    document.addEventListener('focusin', onFocusIn);
    update();

    return () => {
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
      document.removeEventListener('focusin', onFocusIn);
      document.documentElement.style.setProperty('--kb', '0px');
    };
  }, []);
}
