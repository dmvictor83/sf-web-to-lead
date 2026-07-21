<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8"/>
  <script src="https://www.google.com/recaptcha/api.js" async defer></script>
  <script>
    function post(token) { parent.postMessage({ w2l: 'captcha', token: token }, '*'); }
    function w2lOk(token) { post(token); }
    function w2lExpired()  { post(''); }

    function sendSize(h) { parent.postMessage({ w2l: 'captcha-size', height: h }, '*'); }

    function challengeOpen() {
      var f = document.querySelector('iframe[title*="challenge"]');
      if (!f) return false;
      var n = f.parentElement;
      while (n && n !== document.body) {
        var cs = window.getComputedStyle(n);
        if (cs.position === 'fixed') {
          return cs.visibility !== 'hidden' && cs.opacity !== '0';
        }
        n = n.parentElement;
      }
      return false;
    }

    window.addEventListener('load', function () {
      var last = -1;
      setInterval(function () {
        var h = challengeOpen() ? 620 : 90;
        if (h !== last) { last = h; sendSize(h); }
      }, 250);
    });
  </script>
  <style>html,body{margin:0;padding:0;font-family:sans-serif;}</style>
</head>
<body>
  <div class="g-recaptcha"
       data-sitekey="6Lcva14tAAAAAN1XuRMNFBDpuNm1ky_MBIJ-6MJl"
       data-callback="w2lOk"
       data-expired-callback="w2lExpired"></div>
</body>
</html>
