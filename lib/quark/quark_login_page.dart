const quarkWebLoginUrl = 'https://pan.quark.cn/list';

const quarkWebLoginUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// Keep Quark's own form. Select phone login and reveal it on narrow screens;
// never read or fill credential inputs.
const quarkWebLoginLayoutScript = r'''
(() => {
  if (location.hostname !== 'pan.quark.cn') return;
  let attempts = 0;
  const timer = setInterval(() => {
    const phone = [...document.querySelectorAll('div,span,a')].find(element =>
      element.children.length === 0 &&
      element.textContent.trim() === '手机登录' &&
      element.getBoundingClientRect().width > 0);
    if (phone) phone.click();
    const form = [...document.querySelectorAll('iframe')].find(element => {
      try { return new URL(element.src).hostname === 'uop.quark.cn'; }
      catch { return false; }
    });
    if (form && form.getBoundingClientRect().width > 0) {
      form.scrollIntoView({block: 'center', inline: 'center'});
      clearInterval(timer);
    } else if (++attempts >= 40) {
      clearInterval(timer);
    }
  }, 250);
})();
''';
