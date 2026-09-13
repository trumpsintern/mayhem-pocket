const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('mayhem', {
  champions: fresh => ipcRenderer.invoke('champions', fresh),
  build: (champion, fresh) => ipcRenderer.invoke('build', champion, fresh),
  pin: value => ipcRenderer.send('pin', value),
  openOPGG: slug => ipcRenderer.send('open-opgg', slug)
});
