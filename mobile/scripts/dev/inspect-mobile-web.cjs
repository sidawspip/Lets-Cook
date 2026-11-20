// Read-only inspection of the app's debug WebView.
(async () => {
  const tabs = await fetch('http://127.0.0.1:9227/json').then(r => r.json());
  const socket = new WebSocket(tabs[0].webSocketDebuggerUrl);
  socket.onopen = () => socket.send(JSON.stringify({id: 1, method: 'Runtime.evaluate', params: {
    expression: `JSON.stringify({ready:window.__letsCookMediaReady,videos:Array.from(document.querySelectorAll('video')).map(v=>({src:v.currentSrc,paused:v.paused,time:v.currentTime,data:v.dataset}))})`,
    returnByValue: true,
  }}));
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id === 1) {
      console.log(message.result?.result?.value || message.error);
      socket.close();
    }
  };
})();
