import { useEffect } from 'react';
import { isObscured } from './keyboardAvoidance';

export function useKeyboardAvoidance() {
  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;

    function update() {
      // offsetTop accounts for the browser chrome scrolling (e.g. address bar hiding)
      const kb = Math.max(0, window.innerHeight - vv!.height - vv!.offsetTop);
      document.documentElement.style.setProperty('--kb', `${Math.round(kb)}px`);
    }

    // When an input is focused, wait for the keyboard animation, then scroll it
    // into view ONLY if it's actually hidden behind the keyboard. Scrolling an
    // already-visible field (e.g. tapping "Next" between visible inputs) causes a
    // visible flick, so skip it.
    function onFocusIn(e: FocusEvent) {
      const el = e.target as HTMLElement;
      if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
        setTimeout(() => {
          const rect = el.getBoundingClientRect();
          const viewportHeight = vv!.height;
          if (isObscured(rect, viewportHeight)) {
            el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
          }
        }, 300);
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
